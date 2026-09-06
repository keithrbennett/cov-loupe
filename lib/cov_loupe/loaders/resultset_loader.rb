# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../errors/errors'

module CovLoupe
  # Reads and parses a SimpleCov .resultset.json file.
  #
  # Handles both single-suite and multi-suite resultsets. For multi-suite files,
  # it delegates to SimpleCov's ResultsCombiner (requiring the simplecov gem).
  # Legacy resultsets that store raw line arrays (instead of { "lines" => [...] } hashes)
  # are normalized to the newer format.
  #
  # Timestamps are extracted from the "timestamp" or "created_at" fields and normalized
  # to integer epoch seconds. Missing or unparseable timestamps default to 0, which
  # disables time-based staleness checks.
  class ResultsetLoader
    Result = Struct.new(:coverage_map, :timestamp, :suite_names)
    SuiteEntry = Struct.new(:name, :coverage, :timestamp)

    def self.load(resultset_path:, logger: nil)
      logger ||= CovLoupe.logger
      new(resultset_path: resultset_path, logger: logger).load
    end

    def initialize(resultset_path:, logger:)
      @resultset_path = resultset_path
      @logger = logger
    end

    def load
      raw = JSON.parse(File.read(@resultset_path))

      suites = extract_suite_entries(raw)
      if suites.empty?
        raise CoverageDataError,
          "No test suite with coverage data found in resultset file: #{@resultset_path}"
      end

      coverage_map = build_coverage_map(suites)
      Result.new(
        coverage_map: coverage_map,
        timestamp:    compute_combined_timestamp(suites),
        suite_names:  suites.map(&:name)
      )
    end

    private def extract_suite_entries(raw)
      raw
        .select { |_, data| data.is_a?(Hash) && data.key?('coverage') && !data['coverage'].nil? }
        .map do |name, data|
          SuiteEntry.new(
            name:      name.to_s,
            coverage:  normalize_suite_coverage(data['coverage'], suite_name: name),
            timestamp: normalize_coverage_timestamp(data['timestamp'], data['created_at'])
          )
        end
    end

    # Selects coverage strategy based on suite count:
    # - Single suite: use its coverage map directly (no merging needed)
    # - Multiple suites: merge via SimpleCov::Combine::ResultsCombiner (requires simplecov gem)
    private def build_coverage_map(suites)
      return suites.first&.coverage if suites.length == 1

      merge_suite_coverages(suites)
    end

    private def normalize_suite_coverage(coverage, suite_name:)
      unless coverage.is_a?(Hash)
        raise CoverageDataError, "Invalid coverage data structure for suite #{suite_name.inspect} " \
          "in resultset file: #{@resultset_path}"
      end

      needs_adaptation = coverage.values.any?(Array)
      # Older SimpleCov resultsets can store raw line arrays directly under each file key,
      # while newer ones wrap them in a hash with a "lines" entry. The rest of the codebase
      # expects the newer shape, so adapt only the legacy entries here.
      return coverage unless needs_adaptation

      coverage.transform_values do |value|
        value.is_a?(Array) ? { 'lines' => value } : value
      end
    end

    private def merge_suite_coverages(suites)
      require_simplecov_for_merge!
      log_duplicate_suite_names(suites)

      suites.reduce(nil) do |memo, suite|
        coverage = suite.coverage
        memo ?
          SimpleCov::Combine::ResultsCombiner.combine(memo, coverage) :
          coverage
      end
    end

    private def require_simplecov_for_merge!
      require 'simplecov'
    rescue LoadError
      raise CoverageDataError,
        "Multiple coverage suites detected in #{@resultset_path}, but the simplecov gem could not " \
        'be loaded. Install simplecov to enable suite merging.'
    end

    private def log_duplicate_suite_names(suites)
      grouped = suites.group_by(&:name)
      duplicates = grouped.select { |_, entries| entries.length > 1 }.keys
      return if duplicates.empty?

      message = "Merging duplicate coverage suites for #{duplicates.join(', ')}"
      @logger.safe_log(message)
    end

    private def compute_combined_timestamp(suites)
      # compact removes suites with nil timestamps; max on an empty array returns nil,
      # and nil.to_i => 0, which is the sentinel meaning "no timestamp — skip staleness checks".
      suites.map(&:timestamp).compact.max.to_i
    end

    private def normalize_coverage_timestamp(timestamp_value, created_at_value)
      raw = timestamp_value.nil? ? created_at_value : timestamp_value
      return log_missing_timestamp if raw.nil?

      timestamp = case raw
                  when Integer
                    raw
                  when Float, Time
                    raw.to_i
                  when String
                    str = raw.strip
                    # Matches optional leading "-", digits, and an optional fractional part.
                    if str.match?(/\A-?\d+(\.\d+)?\z/)
                      # Some resultsets serialize the epoch as a numeric string instead of
                      # a JSON number. Non-numeric, non-empty strings are handled by the
                      # else branch below via Time.parse.
                      str.to_f.to_i
                    elsif str.empty?
                      0
                    else
                      Time.parse(str).to_i
                    end
                  else
                    log_timestamp_warning(raw)
                    return 0
      end

      timestamp = [timestamp.to_i, 0].max # change negative numbers to zero
      log_missing_timestamp(raw) if timestamp.zero? # but log the original value
      timestamp
    rescue => e
      log_timestamp_warning(raw, e)
      0
    end

    private def log_missing_timestamp(raw_value = nil)
      message = 'Coverage timestamp missing, defaulting to 0. ' \
                'Time-based staleness checks will be disabled.'
      message = "#{message} (value: #{raw_value.inspect})" if raw_value
      @logger.safe_log(message)
      0
    end

    private def log_timestamp_warning(raw_value, error = nil)
      message = "Coverage resultset timestamp could not be parsed: #{raw_value.inspect}"
      message = "#{message} (#{error.message})" if error
      @logger.safe_log(message)
    end
  end
end
