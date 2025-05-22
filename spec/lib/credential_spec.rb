require_relative "../../lib/credential"

describe Credential do
  let!(:credential) do
    Credential.new(
      host: "http://localhost:3000",
      user_id: "user_id",
      api_token: "api_token"
    )
  end

  it "assigns attributes" do
    expect(credential.host).to eq("http://localhost:3000")
    expect(credential.user_id).to eq("user_id")
    expect(credential.api_token).to eq("api_token")
  end
end
