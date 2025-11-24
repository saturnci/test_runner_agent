require_relative "../lib/test_runner_agent"
require_relative "../lib/credential"

require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

describe TestRunnerAgent do
  let!(:test_runner_id) { "674f498b-0669-4581-a0cf-1be4f2cf5a98" }

  let!(:credential) do
    Credential.new(
      host: "https://app.saturnci.com",
      user_id: "test_user_id",
      api_token: "test_api_token"
    )
  end

  let!(:test_runner_agent) do
    TestRunnerAgent.new(test_runner_id:, credential:)
  end

  describe "#send_ready_signal" do
    before do
      stub_request(:post, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_events").
        to_return(status: 200, body: "", headers: {})
    end

    it "works" do
      response = test_runner_agent.send_ready_signal
      expect(response.code).to eq("200")
    end
  end

  describe "#listen_for_assignment" do
    context "an assignment exists" do
      before do
        stub_request(:get, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_assignments").
          to_return(status: 200, body: [{ run_id: "abc123" }].to_json)

        stub_request(:post, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_events")
      end

      it "gets the assignment" do
        assignment = test_runner_agent.listen_for_assignment
        expect(assignment["run_id"]).to eq("abc123")
      end
    end

    context "no assignment exists" do
      before do
        stub_request(:get, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_assignments").
          to_return(status: 200, body: [].to_json)
      end

      it "works" do
        assignment = test_runner_agent.listen_for_assignment(interval_in_seconds: 0, check_limit: 2)
        expect(assignment).to be_nil
      end
    end

    context "error response" do
      before do
        stub_request(:get, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_assignments").
          to_return(status: 500, body: "Internal Server Error", headers: {})
      end

      it "sends an error event" do
        expect(test_runner_agent).to receive(:send_event).with("error")
        test_runner_agent.listen_for_assignment
      end
    end

    context "5 consecutive errors" do
      before do
        stub_request(:get, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_assignments").
          to_return(status: 500, body: "Internal Server Error", headers: {}).times(5)
      end

      it "sends an error event" do
        expect(test_runner_agent).to receive(:send_event).with("error")
        test_runner_agent.listen_for_assignment(interval_in_seconds: 0)
      end
    end

    context "4 consecutive errors followed by a 200" do
      before do
        stub_request(:get, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_assignments").
          to_return(status: 500).times(4).then.
          to_return(status: 200, body: [{ run_id: "abc123" }].to_json)

        stub_request(:post, "https://app.saturnci.com/api/v1/test_runners/#{test_runner_id}/test_runner_events")
      end

      it "does not send an error event" do
        expect(test_runner_agent).not_to receive(:send_event).with("error")
        test_runner_agent.listen_for_assignment(interval_in_seconds: 0)
      end
    end
  end
end
