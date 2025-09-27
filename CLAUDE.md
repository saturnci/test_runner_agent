# CLAUDE.md

## Overview

This project is the test runner agent for SaturnCI, a continuous integration platform for Ruby on Rails projects.
See [SaturnCI](https://www.saturnci.com) for more information.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Testing
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/lib/script_spec.rb` - Run a specific test file  
- `bundle exec rspec spec/lib/script_spec.rb:25` - Run a specific test at line 25

### Dependencies
- `bundle install` - Install Ruby gem dependencies
- `bundle update` - Update gem dependencies

## Architecture Overview

This is a Ruby-based test runner agent for SaturnCI, designed to execute distributed test suites in containerized environments.

### Core Components

**TestRunnerAgent** (`lib/test_runner_agent.rb`) - Main orchestrator that:
- Listens for test assignments from the SaturnCI API
- Manages test execution lifecycle (ready signal, assignment acknowledgment, execution)
- Sets up environment variables from assignments and executes the main script

**Script Execution** (`lib/script.rb`) - The heavy-lifting module containing `execute_script` function that:
- Clones repositories using GitHub tokens
- Builds and caches Docker images with registry authentication
- Manages Docker Compose test environments
- Streams logs and test outputs in real-time
- Handles test file chunking for parallel execution
- Uploads test results and screenshots

**API Communication Layer**:
- `APIRequest` - Low-level HTTP client with authentication
- `Client` - Higher-level SaturnCI API wrapper
- `Stream` - Real-time log streaming to API endpoints
- `FileContentRequest` - File upload handling

**Support Classes**:
- `Credential` - API authentication management
- `TestSuiteCommand` - RSpec command generation
- `DockerRegistryCache` - Docker registry operations and authentication
- `ScreenshotTarFile` - Screenshot collection and compression

### Test Architecture

Tests are split across multiple concurrent runs using:
- RSpec seed-based shuffling for consistent test ordering
- File-based chunking (test files divided by `NUMBER_OF_CONCURRENT_RUNS`)
- Each runner processes a specific chunk based on `RUN_ORDER_INDEX`

### Key Environment Variables

The agent expects these environment variables from test assignments:
- `RUN_ID`, `PROJECT_NAME`, `BRANCH_NAME`, `COMMIT_HASH`
- `NUMBER_OF_CONCURRENT_RUNS`, `RUN_ORDER_INDEX`, `RSPEC_SEED`
- `GITHUB_INSTALLATION_ID`, `GITHUB_REPO_FULL_NAME`
- Docker registry credentials and custom environment variables

### Docker Integration

Uses Docker Buildx for multi-platform builds with:
- Registry caching for performance
- Custom Dockerfile (`.saturnci/Dockerfile`)
- Docker Compose orchestration (`.saturnci/docker-compose.yml`)
- Pre-script execution (`.saturnci/pre.sh`)
