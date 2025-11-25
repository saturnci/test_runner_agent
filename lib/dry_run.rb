class DryRun
  def initialize(docker_service_name:)
    @docker_service_name = docker_service_name
  end

  def command
    "docker compose -f .saturnci/docker-compose.yml run --no-TTY #{@docker_service_name} bundle exec rspec --dry-run"
  end

  def expected_count
    puts "Full dry run output:"
    puts full_output
    puts "Dry run exit code: #{@exit_code}"

    if @exit_code != 0
      raise "RSpec dry-run failed with exit code #{@exit_code}"
    end

    line_with_count = full_output.split("\n").find { |line| line.match(/(\d+) example/) }

    if line_with_count.nil?
      raise "Could not find example count in RSpec dry-run output"
    end

    line_with_count.match(/(\d+) example/)[1].to_i
  end

  def full_output
    @full_output ||= command_output.tap { @exit_code = last_exit_code }
  end

  def command_output
    `#{command} 2>&1`
  end

  def last_exit_code
    $?.exitstatus
  end
end
