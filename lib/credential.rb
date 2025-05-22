class Credential
  attr_reader :host, :user_id, :api_token

  def initialize(host:, user_id:, api_token:)
    raise "Host cannot be nil" if host.nil?
    raise "User ID cannot be nil" if user_id.nil?
    raise "API token cannot be nil" if api_token.nil?

    @host = host
    @user_id = user_id
    @api_token = api_token
  end
end
