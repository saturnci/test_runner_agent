require "net/http"
require "uri"
require "json"
require "fileutils"

require_relative "./client"
require_relative "./stream"
require_relative "./file_content_request"
require_relative "./docker_registry_cache"
require_relative "./test_suite_command"
require_relative "./screenshot_tar_file"

PROJECT_DIR = "/project"
RSPEC_DOCUMENTATION_OUTPUT_FILENAME = "tmp/rspec_documentation_output.txt"
TEST_RESULTS_FILENAME = "tmp/test_results.txt"

def execute_script
  $stdout.sync = true

  client = SaturnCIRunnerAPI::Client.new(ENV["HOST"])

  puts "Starting to stream system logs"
  system_log_stream = SaturnCIRunnerAPI::Stream.new(
    "/var/log/syslog",
    "runs/#{ENV["RUN_ID"]}/system_logs"
  )
  system_log_stream.start

  puts "Test runner agent version: #{`git show -s --format=%ci HEAD`.strip} #{`git rev-parse HEAD`.strip}"
  puts "Runner ready"
  client.post("runs/#{ENV["RUN_ID"]}/run_events", type: "runner_ready")

  FileUtils.rm_rf(PROJECT_DIR) if Dir.exist?(PROJECT_DIR)

  github_token = client.post("github_tokens", github_installation_id: ENV["GITHUB_INSTALLATION_ID"]).body
  clone_repo(
    github_token: github_token,
    source: ENV["GITHUB_REPO_FULL_NAME"],
    destination: PROJECT_DIR
  )

  FileUtils.mkdir_p(PROJECT_DIR)
  Dir.chdir(PROJECT_DIR)
  FileUtils.mkdir_p("tmp")

  client.post("runs/#{ENV["RUN_ID"]}/run_events", type: "repository_cloned")

  puts "Checking out commit #{ENV["COMMIT_HASH"]}"
  system("git checkout #{ENV["COMMIT_HASH"]}")

  dry_run_example_count_endpoint = "test_suite_runs/#{ENV["TEST_SUITE_RUN_ID"]}"
  dry_run_output = `bundle exec rspec --dry-run 2>&1 | tail -2 | head -1`
  puts "Dry run output: #{dry_run_output}"
  dry_run_example_count = dry_run_output.match(/(\d+) example/)[1].to_i
  puts "Sending dry run example count (#{dry_run_example_count}) to API (#{dry_run_example_count_endpoint})"
  response = client.patch(dry_run_example_count_endpoint, { dry_run_example_count: dry_run_example_count })
  puts "Dry run example count response code: #{response.code}"

  docker_registry_cache = SaturnCIRunnerAPI::DockerRegistryCache.new(
    username: ENV["DOCKER_REGISTRY_CACHE_USERNAME"],
    password: ENV["DOCKER_REGISTRY_CACHE_PASSWORD"],
    project_name: ENV["PROJECT_NAME"].downcase,
    branch_name: ENV["BRANCH_NAME"].downcase
  )

  puts "Registry cache image URL: #{docker_registry_cache.image_url}"
  saturnci_env_file_path = File.join(PROJECT_DIR, ".saturnci/.env")
  FileUtils.mv(ENV["SOURCE_ENV_FILE_PATH"], saturnci_env_file_path)
  system("echo 'export SATURN_TEST_APP_IMAGE_URL=#{docker_registry_cache.image_url}' >> #{saturnci_env_file_path}")
  system("export $(cat #{saturnci_env_file_path} | xargs)")

  puts "Environment variables set in this shell:"
  system("env | awk -F= '{print $1}' | sort")

  puts "Project directory contents:"
  system("ls -la")

  puts "Attempting to authenticate to Docker registry (#{SaturnCIRunnerAPI::DockerRegistryCache::URL})"

  if docker_registry_cache.authenticate
    puts "Docker registry cache authentication successful"
  else
    raise "Docker registry cache authentication failed"
  end

  puts "Copying database.yml"
  system("sudo cp .saturnci/database.yml config/database.yml")

  build_args = []
  build_args << "--build-arg ARCH=#{ENV["ARCH"]}" if ENV["ARCH"]
  build_args << "--build-arg NODE_ARCH=#{ENV["NODE_ARCH"]}" if ENV["NODE_ARCH"]
  build_args << "--build-arg BUNDLE_GEMFILE=#{ENV["BUNDLE_GEMFILE"]}" if ENV["BUNDLE_GEMFILE"]
  build_args << "--build-arg BUNDLE_GEMS__CONTRIBSYS__COM=#{ENV["BUNDLE_GEMS__CONTRIBSYS__COM"]}" if ENV["BUNDLE_GEMS__CONTRIBSYS__COM"]
  build_args << "--build-arg BUNDLE_GITHUB__COM=#{ENV["BUNDLE_GITHUB__COM"]}" if ENV["BUNDLE_GITHUB__COM"]
  build_args << "--build-arg GITHUB_TOKEN=#{github_token}"

  system("docker buildx create --name saturnci-builder --driver docker-container --use")

  build_command = "docker buildx build \
    --push \
    -t #{docker_registry_cache.image_url}:latest \
    #{build_args.join(" ")} \
    --cache-from type=registry,ref=#{docker_registry_cache.image_url}:cache \
    --cache-to type=registry,ref=#{docker_registry_cache.image_url}:cache,mode=max \
    --progress=plain \
    -f .saturnci/Dockerfile ."

  puts "Build command: #{build_command}"
  build_command_result = system(build_command)
  if build_command_result
    puts "Build command completed successfully"
  else
    raise "Build command failed"
  end

  puts "Running pre.sh"
  client.post("runs/#{ENV["RUN_ID"]}/run_events", type: "pre_script_started")
  system("sudo chmod 755 .saturnci/pre.sh")

  puts "Environment variables set in this shell:"
  system("env | awk -F= '{print $1}' | sort")

  pre_script_command = "docker compose -f .saturnci/docker-compose.yml run saturn_test_app ./.saturnci/pre.sh"
  puts "pre.sh command: \"#{pre_script_command}\""
  system(pre_script_command)
  puts "pre.sh exit code: #{$?.exitstatus}"

  if $?.exitstatus == 0
    client.post("runs/#{ENV["RUN_ID"]}/run_events", type: "pre_script_finished")
  else
    exit 1
  end

  puts "Starting to stream test output"
  File.open(RSPEC_DOCUMENTATION_OUTPUT_FILENAME, 'w') {}

  SaturnCIRunnerAPI::Stream.new(
    RSPEC_DOCUMENTATION_OUTPUT_FILENAME,
    "runs/#{ENV["RUN_ID"]}/test_output"
  ).start

  puts "Running tests"
  client.post("runs/#{ENV["RUN_ID"]}/run_events", type: "test_suite_started")

  File.open('./example_status_persistence.rb', 'w') do |file|
    file.puts "RSpec.configure do |config|"
    file.puts "  config.example_status_persistence_file_path = '#{TEST_RESULTS_FILENAME}'"
    file.puts "end"
  end

  test_suite_command = SaturnCIRunnerAPI::TestSuiteCommand.new(
    docker_registry_cache_image_url: docker_registry_cache.image_url,
    number_of_concurrent_runs: ENV["NUMBER_OF_CONCURRENT_RUNS"],
    run_order_index: ENV["RUN_ORDER_INDEX"],
    rspec_seed: ENV["RSPEC_SEED"],
    rspec_documentation_output_filename: RSPEC_DOCUMENTATION_OUTPUT_FILENAME
  ).to_s
  puts "Test run command: #{test_suite_command}"

  test_suite_pid = Process.spawn(test_suite_command)
  Process.wait(test_suite_pid)
  sleep(5)

  puts "Sending JSON output"
  test_output_request = SaturnCIRunnerAPI::FileContentRequest.new(
    host: ENV["HOST"],
    api_path: "runs/#{ENV["RUN_ID"]}/json_output",
    content_type: "application/json",
    file_path: "tmp/json_output.json"
  )
  response = test_output_request.execute
  puts "JSON output response code: #{response.code}"
  puts response.body
  puts

  send_screenshot_tar_file(source_dir: "tmp/capybara")

rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace
ensure
  puts "Run finished"
  response = client.post("runs/#{ENV["RUN_ID"]}/run_finished_events")
  puts "Run finished response code: #{response.code}"
  puts response.body
  puts

  puts "Deleting runner"
  puts "Done"
  sleep(5)
  system_log_stream.kill
  client.delete("runs/#{ENV["RUN_ID"]}/runner")
end

def clone_repo(github_token:, source:, destination:)
  require "open3"
  puts "Cloning #{source} into #{destination}..."
  puts "GitHub installation ID: #{ENV["GITHUB_INSTALLATION_ID"]}"
  puts "GitHub token: #{github_token}"
  clone_command = "git clone --recurse-submodules https://x-access-token:#{github_token}@github.com/#{source} #{destination}"
  puts clone_command
  _, stderr, status = Open3.capture3(clone_command)
  puts status.success? ? "clone successful" : "clone failed: #{stderr}"
end

def send_screenshot_tar_file(source_dir:)
  unless Dir.exist?(source_dir)
    puts "No screenshots found in #{source_dir}"
    return
  end

  screenshot_tar_file = SaturnCIRunnerAPI::ScreenshotTarFile.new(source_dir: source_dir)
  puts "Screenshots tarred at: #{screenshot_tar_file.path}"

  screenshot_upload_request = SaturnCIRunnerAPI::FileContentRequest.new(
    host: ENV["HOST"],
    api_path: "runs/#{ENV["RUN_ID"]}/screenshots",
    content_type: "application/tar",
    file_path: screenshot_tar_file.path
  )

  response = screenshot_upload_request.execute
  puts "Screenshot tar response code: #{response.code}"
  puts response.body
end
