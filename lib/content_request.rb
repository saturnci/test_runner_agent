require_relative "api_config"

module SaturnCIRunnerAPI
  class ContentRequest
    include APIConfig
    def initialize(host:, api_path:, content_type:, content:)
      @host = host
      @api_path = api_path
      @content_type = content_type
      @content = content
    end

    def execute
      user_id = ENV["TEST_RUNNER_ID"]
      api_token = ENV["TEST_RUNNER_ACCESS_TOKEN"]

      command = <<~COMMAND
        curl -s -f -u #{user_id}:#{api_token} \
            -X POST \
            -H "Content-Type: #{@content_type}" \
            -d "#{@content}" #{url}
      COMMAND

      system(command)
    end

    private

    def url
      "#{@host}#{API_BASE_PATH}/#{@api_path}"
    end
  end
end
