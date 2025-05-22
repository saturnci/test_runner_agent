require_relative "../../lib/api_request"
require_relative "../../lib/credential"

describe APIRequest do
  let!(:credential) do
    Credential.new(
      host: "http://localhost:3000",
      user_id: "user_id",
      api_token: "api_token"
    )
  end

  let!(:api_request) do
    APIRequest.new(
      credential:,
      method: :get,
      endpoint: "/api/v1/test"
    )
  end

  it "returns 200" do
    allow(api_request).to receive(:http).and_return(double(request: double(code: "200")))
    response = api_request.response

    expect(response.code).to eq("200")
  end
end
