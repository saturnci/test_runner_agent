require_relative "../lib/test_suite_command"

describe SaturnCIRunnerAPI::TestSuiteCommand do
  let!(:command) do
    SaturnCIRunnerAPI::TestSuiteCommand.new(
      docker_registry_cache_image_url: "registrycache.saturnci.com:5000/saturn_test_app:123456",
      number_of_concurrent_runs: "1",
      run_order_index: "1",
      rspec_seed: "999",
      rspec_documentation_output_filename: "tmp/test_output.txt"
    )
  end

  describe "to_s" do
    before do
      allow(command).to receive(:test_files_string).and_return("spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
    end

    it "returns a command" do
      docker_compose_command = "docker compose -f .saturnci/docker-compose.yml run saturn_test_app bundle exec rspec --require ./example_status_persistence.rb --format=documentation --format json --out tmp/json_output.json --order rand:999 spec/models/github_token_spec.rb spec/rebuilds_spec.rb"
      script_env_vars = "SATURN_TEST_APP_IMAGE_URL=registrycache.saturnci.com:5000/saturn_test_app:123456"
      expect(command.to_s).to eq("script -f tmp/test_output.txt -c \"sudo #{script_env_vars} #{docker_compose_command}\"")
    end
  end

  describe "docker_compose_command" do
    before do
      allow(command).to receive(:test_files_string).and_return("spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
    end

    it "returns a command" do
      expect(command.docker_compose_command).to eq("docker compose -f .saturnci/docker-compose.yml run saturn_test_app bundle exec rspec --require ./example_status_persistence.rb --format=documentation --format json --out tmp/json_output.json --order rand:999 spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
    end
  end

  describe "test_files_string" do
    it "works" do
      test_files = ["spec/models/github_token_spec.rb", "spec/rebuilds_spec.rb", "spec/sign_up_spec.rb", "spec/test_spec.rb"]
      expect(command.test_files_string(test_files)).to eq("spec/models/github_token_spec.rb spec/rebuilds_spec.rb spec/sign_up_spec.rb spec/test_spec.rb")
    end
  end
end
