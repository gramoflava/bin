#!/usr/bin/ruby

require 'yaml'
require 'openssl'
require 'net/http'
require 'date'
require 'optparse'
require 'ostruct'

class BBBHelper
  $debug = true

  def self.debug?
    $debug ||= false
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
    stderr.puts "D," + string if debug?
  end

  def self.i(string)
    stderr.puts "I," + string
  end

  def self.w(string)
    stderr.puts "W," + string
  end

  def self.e(string)
    stderr.puts "E," + string
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
    @options.target      = nil
    @options.login       = nil
    @options.password    = nil
    @options.from        = Date.today
    @options.until       = nil
    @options.format      = 'human'
    @options.output_file = nil
    @options.debug       = false

    File.open(CONFIG_FILE) {|f| @options = YAML::load(f) }
  rescue
    @options = {}
    STDERR.puts "W,Unable to read configuration from a file: " + CONFIG_FILE
  end

  def parse(argv)
    OptionParser.new do |opts|
      opts.banner =  "Usage: bbb.rb COMMAND [OPTIONS...]"
      opts.separator "BBBrute exists to help you with the analysis of timesheets"
      opts.separator ""
      opts.separator "COMMAND"
      opts.separator "\thours     - Hours worked by person"
      opts.separator "\twhere     - Where is the person now"
      opts.separator "\tarrive    - First entry"
      opts.separator "\tleave     - Latest exit"
      opts.separator "\tremains   - Remaining workload for a week"
      opts.separator "\tconfigure - Store some settings in the configuration file"
      opts.separator ""

      opts.on('-t', '--target HOST', String, 'https://example.org, Default: from configuration')                  {|s| @options.target      = s }
      opts.on('-l', '--login LOGIN', String, 'User login to access target host, Default: from configuration')     {|s| @options.login       = s }
      opts.on('-p', '--password PASSWORD', String, 'Password to access target host, Default: from configuration') {|s| @options.password    = s }
      opts.on('-i', '--ids ID,..', Array, 'List of ids to check')                                                 {|a| @options.ids         = a.map{|i| Integer(i) } }
      opts.on('-f', '--from DD.MM.YYYY', String, 'First day to request info, Default: today')                     {|s| @options.from        = Date.parse(s) }
      opts.on('-u', '--until DD.MM.YYYY', String, 'First day to request info, Default: FROM')                     {|s| @options.until       = Date.parse(s) }
      opts.on('-f', '--format FORMAT', String, 'Output format (csv, human), Default: human')                      {|s| @options.format      = s }
      opts.on('-o', '--output-file FILENAME', String, 'File to print results')                                    {|s| @options.output_file = s }
      opts.on('-d', '--[no-]debug', 'More info for debug purposes')                                               {|b| @options.debug       = b }

      opts.on_tail('-h', '--help', 'Show help message') do
        puts opts
        exit 0
      end

    end.parse!(argv)
  rescue
    BBBHelper::e "Unexpected error while processing arguments. Resetting to interactive mode…"
  end

  def save
    Dir.mkdir(File.dirname(CONFIG_FILE)) unless Dir.exist?(File.dirname(CONFIG_FILE))
    File.open(CONFIG_FILE) {|f| @options = YAML::load(f) }
  rescue
    @options = {}
    STDERR.puts "W,Unable to read configuration from a file: " + CONFIG_FILE
  end
end


begin

  #  params = parse_argv
  #  bbb = BBBrute.new
  #
  #  BBBHelper::d "Wha?"
  #  bbb.auth
  #
  #  BBBHelper::write_html_header(OUTPUT_FILE)
  #
  #  start_date = Date.today - 1
  #
  #  bbb.doors({:id => id, :start_date => start_date})
  #

  parse_options

rescue => exception
  STDERR.puts "E: #{exception}"
  raise exception
end
