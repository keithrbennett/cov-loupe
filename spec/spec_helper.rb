# frozen_string_literal: true

# Enable SimpleCov for this project (coverage output in ./coverage)
begin
  require 'simplecov'
  require 'simplecov-cobertura'
  SimpleCov.start do
    add_filter(%r{^/spec/})
    track_files 'lib/**/*.rb'
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::CoberturaFormatter,
    ])
  end

  # Report lowest coverage files at the end of the test run
  SimpleCov.at_exit do
    SimpleCov.result.format!
    require 'cov_loupe'
    report = CovLoupe::CoverageReporter.report(threshold: 80, count: 5)
    puts report if report
  end
rescue LoadError
  warn 'SimpleCov not available; skipping coverage'
end


require 'rspec'
require 'pathname'
require 'json'

# Load core cov_loupe module first, then load all components for testing (CLI, MCP server, tools)
# Library users should use 'require "cov_loupe"' to load only core components
require 'cov_loupe'
require 'cov_loupe/loaders/all'

FIXTURES_DIR = Pathname.new(File.expand_path('fixtures', __dir__))
FIXTURE_PROJECT1_RESULTSET_PATH = (FIXTURES_DIR / 'project1' / 'coverage' / '.resultset.json').to_s

# Test timestamp constants for consistent and documented test data
# Main fixture coverage timestamp: 1720000000 = 2024-07-03 16:26:40 UTC
# This represents when the coverage data in spec/fixtures/project1/coverage/.resultset.json was "generated"
FIXTURE_COVERAGE_TIMESTAMP = 1_720_000_000

# Very old timestamp: 1 = 1970-01-01 00:00:01 UTC (Unix epoch + 1s)
# Used in tests to simulate stale coverage (much older than any real file)
# Note: 0 is reserved for missing/invalid timestamps which disable staleness checks.
VERY_OLD_TIMESTAMP = 1

# Test timestamps for stale error formatting tests
# 1000 = 1970-01-01 00:16:40 UTC (16 minutes and 40 seconds after epoch)
TEST_FILE_TIMESTAMP = 1_000

# Regex pattern for matching ISO 8601 timestamps with brackets in log output
# Used to verify log timestamps in tests
TIMESTAMP_REGEX = /\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\]/

# Default timeout for integration tests (longer on JRuby due to startup overhead)
INTEGRATION_TIMEOUT = RUBY_PLATFORM.include?('java') ? 15 : 5

# Helper method to mock resultset file reading with fake coverage data
# @param root [String] The test root directory
# @param timestamp [Integer] The timestamp to use in the fake resultset
# @param coverage [Hash] Optional custom coverage data (default: basic foo.rb and bar.rb)
def mock_resultset_with_timestamp(root, timestamp, coverage: nil)
  mock_resultset_with_metadata(root, { 'timestamp' => timestamp }, coverage: coverage)
end

def mock_resultset_with_created_at(root, created_at, coverage: nil)
  mock_resultset_with_metadata(root, { 'created_at' => created_at }, coverage: coverage)
end

def mock_resultset_with_metadata(root, metadata, coverage: nil)
  abs_root = File.absolute_path(root)
  default_coverage = {
    File.join(root, 'lib', 'foo.rb') => { 'lines' => [1, 0, nil, 2] },
    File.join(root, 'lib', 'bar.rb') => { 'lines' => [0, 0, 1] },
  }

  fake_resultset_hash = {
    'RSpec' => {
      'coverage' => coverage || default_coverage,
    }.merge(metadata),
  }

  allow(File).to receive(:read).and_call_original # Allow real File.read for other calls

  allow(File).to receive(:read).with(end_with('.resultset.json'))
    .and_return(JSON.generate(fake_resultset_hash))
  allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file)
    .and_wrap_original do |method, search_root, coverage_file: nil|
    mock_path = File.join(abs_root, 'coverage', '.resultset.json')
    is_mock_target = coverage_file.nil? || coverage_file.to_s.empty? ||
      File.absolute_path(coverage_file.to_s) == File.absolute_path(mock_path)

    if File.absolute_path(search_root) == abs_root && is_mock_target
      mock_path
    else
      method.call(search_root, coverage_file: coverage_file)
    end
  end
end

# Automatically require all files in spec/support and spec/shared_examples
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }
Dir[File.join(__dir__, 'cov_loupe', 'shared_examples', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  # Randomize spec order to expose order dependencies; pass --seed to reproduce failures
  config.order = :random
  Kernel.srand config.seed

  # Suppress logging during tests by redirecting to /dev/null
  # This is cheap and doesn't break tests that verify logging behavior
  CovLoupe.default_log_file = File::NULL
  CovLoupe.active_log_file = File::NULL

  # Deprecation warnings are off by default so specs exercising deprecated
  # names do not write to stderr. Specs that assert on the warnings turn them
  # back on for their own examples.
  CovLoupe::Deprecation.enabled = false

  # Reset log file after each test to ensure tests that change it don't pollute others
  config.after do
    CovLoupe.active_log_file = File::NULL
  end

  config.before do
    CovLoupe::ModelDataCache.instance.clear
  end

  config.include TestIOHelpers
  config.include CLITestHelpers
  config.include MCPToolTestHelpers
  config.include MockingHelpers
  config.include ControlFlowHelpers
  config.include ResultsetMockHelpers
  config.include Spec::Support::McpIntegrationHelpers
end

# Custom matchers
# Matcher used across CLI tests to assert that source output was produced.
# Commands either print a formatted table (with a "Line | Source" header) or a
# fallback message when the source cannot be shown. This matcher accepts either.
RSpec::Matchers.define :show_source_table_or_fallback do
  match do |output|
    has_table_header = output.match?(/(^|\n)\s*Line\s*\|\s+Source/)
    has_fallback = output.include?('[source not available]')
    has_table_header || has_fallback
  end

  failure_message do |_output|
    "expected output to include a source table header (e.g., 'Line | Source') " \
      "or the fallback '[source not available]'"
  end
end
