module SaturnCIRunnerAPI
  class ContentRequest
    def initialize(host:, api_path:, content_type:, content:)
      @host = host
      @api_path = api_path
      @content_type = content_type
      @content = content
    end

    def execute
      user_id = ENV["SATURNCI_USER_ID"] || ENV["USER_ID"]
      api_token = ENV["SATURNCI_USER_API_TOKEN"] || ENV["USER_API_TOKEN"]

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
      "#{@host}/api/v1/#{@api_path}"
    end
  end
end
