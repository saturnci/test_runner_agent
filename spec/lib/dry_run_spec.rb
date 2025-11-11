require_relative "../../lib/dry_run"

describe DryRun do
  let!(:dry_run) do
    DryRun.new(docker_service_name: "saturn_test_app")
  end

  let!(:command_output) do
    <<~OUTPUT
    ................

    Finished in 0.00146 seconds (files took 0.13094 seconds to load)
    16 examples, 0 failures
    OUTPUT
  end

  before do
    allow(dry_run).to receive(:command_output).and_return(command_output)
    allow(dry_run).to receive(:last_exit_code).and_return(0)
  end

  describe "#command" do
    it "returns the dry run command" do
      expected_command = "docker compose -f .saturnci/docker-compose.yml run saturn_test_app bundle exec rspec --dry-run"
      expect(dry_run.command).to eq(expected_command)
    end
  end

  describe "#full_output" do
    context "output is called multiple times" do
      it "only runs the command once" do
        expect(dry_run.full_output).to eq(command_output)
        allow(dry_run).to receive(:command_output).and_return("blah")
        expect(dry_run.full_output).to eq(command_output)
      end
    end
  end

  describe "#expected_count" do
    it "is 16" do
      expect(dry_run.expected_count).to eq(16)
    end
  end

  context "exit code is not 0" do
    before do
      allow(dry_run).to receive(:last_exit_code).and_return(1)
    end

    it "raises an error" do
      expect { dry_run.expected_count }.to raise_error("RSpec dry-run failed with exit code 1")
    end
  end
end
