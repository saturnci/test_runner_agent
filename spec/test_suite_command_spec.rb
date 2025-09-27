require_relative "../lib/test_suite_command"

describe SaturnCIRunnerAPI::TestSuiteCommand do
  describe "to_s" do
    let!(:command) do
      SaturnCIRunnerAPI::TestSuiteCommand.new(
        docker_registry_cache_image_url: "registrycache.saturnci.com:5000/saturn_test_app:123456",
        number_of_concurrent_runs: "1",
        run_order_index: "1",
        rspec_seed: "999",
        rspec_documentation_output_filename: "tmp/test_output.txt"
      )
    end

    before do
      allow(command).to receive(:test_filenames_string).and_return("spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
    end

    it "returns a command" do
      docker_compose_command = "docker compose -f .saturnci/docker-compose.yml run saturn_test_app bundle exec rspec --require ./example_status_persistence.rb --format=documentation --format json --out tmp/json_output.json --order rand:999 spec/models/github_token_spec.rb spec/rebuilds_spec.rb"
      script_env_vars = "SATURN_TEST_APP_IMAGE_URL=registrycache.saturnci.com:5000/saturn_test_app:123456"
      expect(command.to_s).to eq("script -f tmp/test_output.txt -c \"sudo #{script_env_vars} #{docker_compose_command}\"")
    end
  end

  describe "docker_compose_command" do
    let!(:command) do
      SaturnCIRunnerAPI::TestSuiteCommand.new(
        docker_registry_cache_image_url: "registrycache.saturnci.com:5000/saturn_test_app:123456",
        number_of_concurrent_runs: "1",
        run_order_index: "1",
        rspec_seed: "999",
        rspec_documentation_output_filename: "tmp/test_output.txt"
      )
    end

    before do
      allow(command).to receive(:test_filenames_string).and_return("spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
    end

    it "returns a command" do
      expect(command.docker_compose_command).to eq("docker compose -f .saturnci/docker-compose.yml run saturn_test_app bundle exec rspec --require ./example_status_persistence.rb --format=documentation --format json --out tmp/json_output.json --order rand:999 spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
    end
  end

  describe "test_filenames_string" do
    context "concurrency 2, order index 1" do
      let!(:command) do
        SaturnCIRunnerAPI::TestSuiteCommand.new(
          docker_registry_cache_image_url: "registrycache.saturnci.com:5000/saturn_test_app:123456",
          number_of_concurrent_runs: "2",
          run_order_index: "1",
          rspec_seed: "999",
          rspec_documentation_output_filename: "tmp/test_output.txt"
        )
      end

      it "includes the first two test files" do
        test_filenames = ["spec/models/github_token_spec.rb", "spec/rebuilds_spec.rb", "spec/sign_up_spec.rb", "spec/test_spec.rb"]
        expect(command.test_filenames_string(test_filenames)).to eq("spec/models/github_token_spec.rb spec/rebuilds_spec.rb")
      end
    end

    context "concurrency 2, order index 2" do
      let!(:command) do
        SaturnCIRunnerAPI::TestSuiteCommand.new(
          docker_registry_cache_image_url: "registrycache.saturnci.com:5000/saturn_test_app:123456",
          number_of_concurrent_runs: "2",
          run_order_index: "2",
          rspec_seed: "999",
          rspec_documentation_output_filename: "tmp/test_output.txt"
        )
      end

      it "includes the second two test files" do
        test_filenames = ["spec/models/github_token_spec.rb", "spec/rebuilds_spec.rb", "spec/sign_up_spec.rb", "spec/test_spec.rb"]
        expect(command.test_filenames_string(test_filenames)).to eq("spec/sign_up_spec.rb spec/test_spec.rb")
      end
    end

    context "no test files" do
      let!(:command) do
        SaturnCIRunnerAPI::TestSuiteCommand.new(
          docker_registry_cache_image_url: "registrycache.saturnci.com:5000/saturn_test_app:123456",
          number_of_concurrent_runs: "2",
          run_order_index: "2",
          rspec_seed: "999",
          rspec_documentation_output_filename: "tmp/test_output.txt"
        )
      end

      it "raises an exception" do
        test_filenames = []
        expect { command.test_filenames_string(test_filenames) }.to raise_error(StandardError)
      end
    end

    context "chunking bug reproduction: 77 files with 4 runners" do
      it "distributes all 77 files across 4 runners without losing any" do
        test_filenames = (1..77).map { |i| "spec/test_#{i}_spec.rb" }

        all_distributed_files = []

        (1..4).each do |run_order_index|
          command = SaturnCIRunnerAPI::TestSuiteCommand.new(
            docker_registry_cache_image_url: "test.com/image:123",
            number_of_concurrent_runs: "4",
            run_order_index: run_order_index.to_s,
            rspec_seed: "999",
            rspec_documentation_output_filename: "tmp/test_output.txt"
          )

          files_string = command.test_filenames_string(test_filenames)
          files_array = files_string.split(' ')
          all_distributed_files.concat(files_array)
        end

        expect(all_distributed_files.length).to eq(77)
      end
    end
  end
end
