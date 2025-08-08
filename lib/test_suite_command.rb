module SaturnCIRunnerAPI
  class TestSuiteCommand
    TEST_FILE_GLOB = "./spec/**/*_spec.rb"

    def initialize(docker_registry_cache_image_url:, number_of_concurrent_runs:, run_order_index:, rspec_seed:, rspec_documentation_output_filename:)
      @docker_registry_cache_image_url = docker_registry_cache_image_url
      @number_of_concurrent_runs = number_of_concurrent_runs.to_i
      @run_order_index = run_order_index.to_i
      @rspec_seed = rspec_seed.to_i
      @rspec_documentation_output_filename = rspec_documentation_output_filename
    end

    def to_s
      "script -f #{@rspec_documentation_output_filename} -c \"sudo SATURN_TEST_APP_IMAGE_URL=#{@docker_registry_cache_image_url} #{docker_compose_command.strip}\""
    end

    def docker_compose_command
      "docker compose -f .saturnci/docker-compose.yml run saturn_test_app #{rspec_command}"
    end

    def test_files_string(test_files)
      raise StandardError, "No test files found matching #{TEST_FILE_GLOB}" if test_files.empty?
      slice_size = test_files.size / @number_of_concurrent_runs
      chunks = test_files.each_slice(slice_size.to_f.ceil).to_a
      selected_tests = chunks[@run_order_index - 1]
      selected_tests.join(" ")
    end

    private

    def rspec_command
      [
        "bundle exec rspec",
        "--require ./example_status_persistence.rb",
        "--format=documentation",
        "--format json --out tmp/json_output.json",
        "--order rand:#{@rspec_seed}",
        test_files_string(test_files)
      ].join(' ')
    end

    def test_files
      Dir.glob(TEST_FILE_GLOB).shuffle(random: Random.new(@rspec_seed))
    end
  end
end
