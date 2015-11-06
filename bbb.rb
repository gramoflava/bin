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

  HTML_HEADER = "<html>\n<head>\n<title>Результаты</title>\n<meta http-equiv='Content-Type' content='text/html; charset=utf-8' />\n</head>\n<body>\n<ul style='list-style: none;'>"
  HTML_FOOTER = "</ul>\n</body>\n</html>"

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

  def self.d(string)
    STDERR.puts "D," + string if debug?
  end

  def self.i(string)
    STDERR.puts "I," + string
  end

  def self.w(string)
    STDERR.puts "W," + string if debug?
  end

  def self.e(string)
    STDERR.puts "E," + string
  end

  def self.write_html_header(filename)
    File.open(filename, "w") do |file|
      file.puts(HTML_HEADER)
    end
  end

  def self.write_html_li(filename, li)
    File.open(filename, "a+") do |file|
      file.puts(li)
    end
  end

  def self.write_html_footer(filename)
    File.open(filename, "a+") do |file|
      file.puts(HTML_FOOTER)
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

  LOGIN_PAGE       = 'misc/login.asp'
  DOORS_PAGE       = 'Door/DoorPers.asp'

  def initialize
    load_credentials

    @bbb_uri = URI(target)
    @bbb_login_uri = URI.join(target, LOGIN_PAGE)
    @bbb_doors_uri = URI.join(target, DOORS_PAGE)

    @http = Net::HTTP.start(bbb_uri.host, bbb_uri.port, use_ssl: uri.scheme == 'https', verify_mode: OpenSSL::SSL::VERIFY_NONE)
  end

  def ask_credentials
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
    request = Net::HTTP::Get.new(login_uri.request_uri)
    request.basic_auth(credentials[:login], credentials[:password])
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

  def doors(param)
    id = param[:id]
    start_date = param[:start_date]
    end_date = param[:end_date]
    end_date ||= start_date

    url = "https://#{TARGET_HOST}/#{DOORS_PAGE}?" + query(STAT::Times, {:id => id, :bdate => start_date, :edate => end_date})
    uri = URI(url)

    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(credentials[:login], credentials[:password])
    request.add_field("cookie", $cookies)
    response = @http.request(request)

    BBBHelper::debug_http_get_print_headers(request)
    BBBHelper::debug_http_response_print_headers(response)

    BBBHelper::d "#{id} #{response.inspect}"

    body = response.body

    link = body.match(/<a href=\.\.\/misc\/PersInfo\.asp\?ID=#{id}>(.*)<\/a>/)

    unless link.nil?
      li = "<li>#{id} &rarr; <a href='#{uri}'>#{link[1].force_encoding('CP1251').encode('UTF-8')}</a></li>"
      BBBHelper::write_html_li(OUTPUT_FILE, li)
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
  opts = BBBOptions.new
  opts.parse
  BBBHelper.debug = opts.debug

  BBBHelper.d "Parsed options: " + opts.get_options.to_s

  case opts.command
  when 'save'
    opts.save_config
  end

rescue => exception
  STDERR.puts "E: #{exception}"
  raise exception
end
