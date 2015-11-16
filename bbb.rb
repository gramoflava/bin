#!/usr/bin/ruby

require 'yaml'
require 'openssl'
require 'net/http'
require 'date'
require 'optparse'
require 'ostruct'
require 'base64'

class BBBHelper
  def self.debug?
    @debug ||= false
  end

  def self.debug=(value)
    @debug = value
  end

  def self.debug_http_get_print_headers(request)
    return unless debug?

    STDERR.puts "GET Request:"
    STDERR.puts request.path
    request.each_header {|key,value| STDERR.puts "| #{key} = #{value}" }
  end

  def self.debug_http_response_print_headers(response)
    return unless debug?

    STDERR.puts "Response:"
    STDERR.puts response.inspect
    response.header.each_header {|key,value| STDERR.puts "| #{key} = #{value}" }
  end

  def self.http_extract_cookies(response)
    all_cookies = response.get_fields('set-cookie')
    unless all_cookies == nil
      cookies_array = Array.new
      all_cookies.each { |cookie|
        cookies_array.push(cookie.split('; ')[0])
      }
      $cookies = cookies_array.join('; ')
    end
  rescue
    raise "Cookies not extracted for an unknown reason."
  end

  def self.d(lines)
    if debug?
      lines.split("\n").each do |line|
        STDERR.puts "D,#{line}"
      end
    end
  end

  def self.w(lines)
    if debug?
      lines.split("\n").each do |line|
        STDERR.puts "W,#{line}"
      end
    end
  end

  def self.e(lines)
    if debug?
      lines.split("\n").each do |line|
        STDERR.puts "E,#{line}"
      end
    end
  end
end

class BBBrute
  module STAT
    Lateness  =  0
    Absence   =  1
    Times     =  2
    Doors     =  3
  end

  LOGIN_PAGE = 'misc/login.asp'
  DOORS_PAGE = 'Door/DoorPers.asp'
  USERAGENT  = 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:40.0) Gecko/20100101 Firefox/40.1'

  def initialize(options)
    @options = options

    uri = URI(@options.target)

    @http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', verify_mode: OpenSSL::SSL::VERIFY_NONE)
  end

  def query(stat, params)
    id = params[:id]
    bdate = params[:bdate]
    edate = params[:edate]
    query = "Bt=%CF%EE%E8%F1%EA&Period=0"
    query += "&RG=#{stat}"
    query += "&Empl=#{id}" if id
    query += "&bD=#{bdate.day}&bMn=#{bdate.month}&bYr=#{bdate.year}"
    query += "&eD=#{edate.day}&eMn=#{edate.month}&eYr=#{edate.year}"
  end

  def auth
    uri = URI.join(@options.target, LOGIN_PAGE)
    request = Net::HTTP::Get.new(uri.request_uri, {'user-agent' => USERAGENT})
    request.basic_auth(@options.login, @options.password)
    response = @http.request(request)

    BBBHelper::debug_http_get_print_headers(request)
    BBBHelper::debug_http_response_print_headers(response)

    raise "Authorization failed (401)" if response.code == '401'

    $cookies = BBBHelper::http_extract_cookies(response)
  end

  def cwb(date = Date.today)
    date - date.wday + 1
  end

  def cwe(date = Date.today)
    date - date.wday + 7
  end

  def doors
    uri = URI.join(@options.target + "/" + DOORS_PAGE + "?" + query(STAT::Times, {:id => @options.id, :bdate => @options.from, :edate => @options.until}))

    request = Net::HTTP::Get.new(uri.request_uri, {'user-agent' => USERAGENT})
    request.basic_auth(@options.login, @options.password)
    request.add_field("cookie", $cookies)
    response = @http.request(request)

    BBBHelper::debug_http_get_print_headers(request)
    BBBHelper::debug_http_response_print_headers(response)

    BBBHelper::d "#{@options.id} #{response.inspect}"

    body = response.body.force_encoding('CP1251').encode('UTF-8')

    BBBHelper::d "BODY"
    BBBHelper::d body
    BBBHelper::d "END BODY"

    link = body.match(/<a href=\.\.\/misc\/PersInfo\.asp\?ID=[0-9]+>(.*)<\/a>/)

    unless link.nil?
      puts link
    end
  end
end


class BBBOptions
  CONFIG_FILE = File.join(Dir.home, '.bbb/config.yml')

  def initialize
    @options = OpenStruct.new
    @options.command          = nil
    @options.target           = nil
    @options.login            = nil
    @options.password         = nil
    @options.ids              = []
    @options.from             = Date.today
    @options.until            = @options.from
    @options.machine_friendly = false
    @options.debug            = false

    load_config
    setup_parser
  end

  def method_missing(method, *args, &block)
    @options.send(method, *args, &block)
  end

  def setup_parser
    @parser = OptionParser.new

    @parser.banner =  "Usage: bbb.rb COMMAND [OPTIONS...]"
    @parser.separator "BBBrute exists to help you with the analysis of timesheets"
    @parser.separator ""
    @parser.separator "COMMAND"
    @parser.separator "\thours     - Hours worked by person"
    @parser.separator "\twhere     - Where is the person now"
    @parser.separator "\tarrive    - First entry"
    @parser.separator "\tleave     - Latest exit"
    @parser.separator "\tremains   - Remaining workload for a week"
    @parser.separator "\tsave      - Store access settings in the configuration file"
    @parser.separator ""

    @parser.on('-t', '--target HOST', String,
               'https://example.org, Default: From configuration') do |s|
      @options.target = s
    end

    @parser.on('-l', '--login LOGIN', String,
               'User login to access target host, Default: From configuration') do |s|
      @options.login = s
    end

    @parser.on('-p', '--password PASSWORD', String,
               'Password to access target host, Default: From configuration') do |s|
      @options.password = s
    end

    @parser.on('-i', '--ids ID,..', Array, 'List of ids to check') do |a|
      @options.ids = a.map{|i| Integer(i) }
    end

    @parser.on('-f', '--from DD.MM.YYYY', String,
               'First day to request info, Default: today') do |s|
      @options.from = Date.parse(s)
    end

    @parser.on('-u', '--until DD.MM.YYYY', String,
               'First day to request info, Default: FROM') do |s|
      @options.until = Date.parse(s)
    end

    @parser.on('-m', '--[no-]machine-friendly',
               'Output format in CSV') do |b|
      @options.machine_friendly = b
    end

    @parser.on('-d', '--[no-]debug',
               'More info for debug purposes') do |b|
      @options.debug = b
    end

    @parser.on_tail('-h', '--help',
                    'Show help message') do
      puts @parser
      exit 0
    end
  rescue => e
    BBBHelper.e 'Error in the options parser configuration.'
  end

  def load_config
    File.open(CONFIG_FILE) do |f|
      config = YAML::load(f)

      @options.target   = config[:target]
      @options.login    = config[:login]
      @options.password = Base64.decode64(config[:password])

      BBBHelper.d "Configuration loaded from the file: " + CONFIG_FILE
    end
  rescue => e
    BBBHelper.w "Unable to load configuration from the file: " + CONFIG_FILE
  end

  def save_config
    config = {
      :target => @options.target,
      :login => @options.login,
      :password => Base64.encode64(@options.password)
    }

    Dir.mkdir(File.dirname(CONFIG_FILE)) unless Dir.exist?(File.dirname(CONFIG_FILE))
    File.open(CONFIG_FILE, mode = "w") do |f|
      f.puts(config.to_yaml)
    end

    puts "Configuration written to the file: " + CONFIG_FILE
  rescue => e
    BBBHelper.e "Unable to write configuration to the file(#{CONFIG_FILE})"
    raise e
  end

  def parse(argv = ARGV)
    @options.command = argv.shift
    @parser.parse(argv)
  rescue => e
    BBBHelper::e "Unexpected error while processing arguments. Resetting to interactive mode…"
    raise e
  end

  def get_options
    @options.to_h
  end
end


begin
  options = BBBOptions.new

  options.parse(ARGV)

  BBBHelper.debug = options.debug
  BBBHelper.d "Parsed options: " + options.get_options.to_s

  case options.command
  when 'doors'
    b = BBBrute.new(options)
    b.auth
    b.doors

  when 'save'
    options.save_config
  else
    BBBHelper.e "Unrecognized command: " + options.command.to_s
    exit 1
  end
rescue => exception
  STDERR.puts "E: #{exception}"
  raise exception
end
