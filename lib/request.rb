require "net/http"
require "uri"
require "json"

module SaturnCIRunnerAPI
  class Request
    def initialize(host, method, endpoint, body = nil)
      @host = host
      @method = method
      @endpoint = endpoint
      @body = body
    end

    def execute
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true if url.scheme == "https"
      http.request(request)
    rescue => e
      puts "Request failed at #{Time.now}: #{e.message}"
      puts "Resolv.conf: #{File.read('/etc/resolv.conf') rescue 'FILE NOT FOUND'}"

      # Test if local DNS resolver works
      dig_result = `dig @127.0.0.53 app.saturnci.com +short +time=1 2>&1`.strip
      if dig_result.include?("connection timed out") || dig_result.include?("no servers could be reached")
        puts "Local DNS resolver: NOT RESPONDING"
      elsif dig_result.match(/^\d+\.\d+\.\d+\.\d+/)
        puts "Local DNS resolver: WORKING (resolved to #{dig_result})"
      elsif dig_result.include?("SERVFAIL") || dig_result.include?("NXDOMAIN")
        puts "Local DNS resolver: RESPONDING but cannot resolve domain"
      else
        puts "Local DNS resolver: UNKNOWN STATUS (#{dig_result})"
      end

      puts "NSSwitch hosts config: #{File.read('/etc/nsswitch.conf').lines.grep(/^hosts:/).first&.strip || 'NOT FOUND'}"

      # Test Ruby's direct DNS resolution (bypasses NSS)
      begin
        require 'resolv'
        ip = Resolv.getaddress('app.saturnci.com')
        puts "Ruby direct DNS: #{ip}"
      rescue => dns_error
        puts "Ruby direct DNS: FAILED (#{dns_error.message})"
      end

      raise e
    end

    def request
      case @method
      when :post
        r = Net::HTTP::Post.new(url)
      when :delete
        r = Net::HTTP::Delete.new(url)
      when :patch
        r = Net::HTTP::Patch.new(url)
      end

      r.basic_auth(ENV["SATURNCI_USER_ID"] || ENV["USER_ID"], ENV["SATURNCI_USER_API_TOKEN"] || ENV["USER_API_TOKEN"])
      r["Content-Type"] = "application/json"
      r.body = @body.to_json if @body
      r
    end

    private

    def url
      URI("#{@host}/api/v1/#{@endpoint}")
    end
  end
end
