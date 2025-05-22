require "net/http"
require "uri"
require "json"

class APIRequest
  def initialize(credential:, method:, endpoint:, body: {}, debug: false)
    @credential = credential
    @method = method
    @endpoint = endpoint
    @body = body
    @debug = debug

    @uri = URI("#{@credential.host}/api/v1/#{@endpoint}")
  end

  def response
    if @debug
      puts "Request details:"
      puts @uri.scheme
      puts @uri.hostname
      puts @uri.path
      puts @uri.port
      puts
    end

    http.request(request).tap do |response|
      if @debug
        puts "Response:"
        puts "#{response.code} #{response.message}"
        puts response.body
      end
    end
  end

  def http
    Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: use_ssl?)
  end

  def use_ssl?
    @uri.scheme == "https"
  end

  private

  def request
    method.new(@uri).tap do |request|
      request.basic_auth @credential.user_id, @credential.api_token
      request.content_type = "application/json"
      request.body = @body.to_json
    end
  end

  def method
    case @method
    when :get
      Net::HTTP::Get
    when :patch
      Net::HTTP::Patch
    when :post
      Net::HTTP::Post
    else
      raise "Unknown method: #{@method}"
    end
  end
end
