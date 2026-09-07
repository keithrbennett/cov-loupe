# frozen_string_literal: true

require 'json'
require 'time'

# Helpers for building and mocking SimpleCov coverage.json documents.
module CoverageFileMockHelpers
  SCHEMA_URL = 'https://raw.githubusercontent.com/simplecov-ruby/simplecov/main/schemas/coverage-v1.0.schema.json'

  # Builds a SimpleCov 1.0 JSON formatter document around the given coverage map.
  # An Integer timestamp is written the way SimpleCov writes it (ISO 8601, ms
  # precision); a String is written as given; nil omits meta.timestamp.
  def coverage_json_document(coverage:, timestamp: FIXTURE_COVERAGE_TIMESTAMP, command_name: 'RSpec')
    meta = {
      'schema_version'    => '1.0',
      'simplecov_version' => '1.0.0',
      'command_name'      => command_name,
    }
    meta['timestamp'] = timestamp.is_a?(Numeric) ? Time.at(timestamp).utc.iso8601(3) : timestamp if timestamp
    {
      '$schema'  => SCHEMA_URL,
      'meta'     => meta,
      'coverage' => coverage,
      'groups'   => {},
      'errors'   => {},
    }
  end

  # Mocks coverage.json under root/coverage with the given timestamp and
  # coverage map (default: basic foo.rb and bar.rb), and makes the resolver
  # return that path for root when no other coverage file is requested.
  def mock_coverage_with_timestamp(root, timestamp, coverage: nil)
    abs_root = File.absolute_path(root)
    default_coverage = {
      File.join(root, 'lib', 'foo.rb') => { 'lines' => [1, 0, nil, 2] },
      File.join(root, 'lib', 'bar.rb') => { 'lines' => [0, 0, 1] },
    }
    document = coverage_json_document(coverage: coverage || default_coverage, timestamp: timestamp)

    allow(File).to receive(:read).and_call_original # Allow real File.read for other calls
    allow(File).to receive(:read).with(end_with('coverage.json')).and_return(JSON.generate(document))

    allow(CovLoupe::Resolvers::ResolverHelpers).to receive(:find_coverage_file)
      .and_wrap_original do |method, search_root, coverage_file: nil|
      mock_path = File.join(abs_root, 'coverage', 'coverage.json')
      is_mock_target = coverage_file.nil? || coverage_file.to_s.empty? ||
        File.absolute_path(coverage_file.to_s) == File.absolute_path(mock_path)

      if File.absolute_path(search_root) == abs_root && is_mock_target
        mock_path
      else
        method.call(search_root, coverage_file: coverage_file)
      end
    end
  end

  # Mock File.read to raise an error (for file system errors like EACCES, ENOENT)
  # Defaults to matching coverage.json files only, allowing other File.read calls to work normally
  def mock_file_read_error(error, path_matcher: end_with('coverage.json'))
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(path_matcher).and_raise(error)
  end

  # Mock JSON.parse to raise an error (for JSON parsing errors)
  # Defaults to matching coverage.json files only
  def mock_json_parse_error(error, json_content: 'invalid json')
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(end_with('coverage.json')).and_return(json_content)
    allow(JSON).to receive(:parse).with(json_content).and_raise(error)
  end

  # Mock File.read to return the given data as JSON
  # Defaults to matching coverage.json files only, allowing other File.read calls to work normally
  def mock_coverage_data(data, path_matcher: end_with('coverage.json'))
    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(path_matcher).and_return(JSON.generate(data))
  end
end
