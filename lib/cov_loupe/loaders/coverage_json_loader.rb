# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../errors/errors'

module CovLoupe
  # Reads and parses a SimpleCov coverage.json file: the JSON formatter
  # output that SimpleCov 1.0.0 and later write alongside the HTML report,
  # described by a versioned JSON schema in the simplecov repository.
  #
  # The document carries a single already-merged coverage map under
  # "coverage", so no suite merging is needed. File keys are project-relative;
  # CoverageRepository expands them against the project root.
  #
  # The timestamp comes from meta.timestamp (ISO 8601) and is normalized to
  # integer epoch seconds. A missing or unparseable timestamp becomes 0, which
  # disables time-based staleness checks.
  class CoverageJsonLoader
    Result = Struct.new(:coverage_map, :timestamp)

    # Sentinel the JSON formatter writes for lines excluded from coverage.
    IGNORED_LINE = 'ignored'

    def self.load(resolved_coverage_file:, logger: nil)
      logger ||= CovLoupe.logger
      new(resolved_coverage_file: resolved_coverage_file, logger: logger).load
    end

    def initialize(resolved_coverage_file:, logger:)
      @resolved_coverage_file = resolved_coverage_file
      @logger = logger
    end

    def load
      raw = JSON.parse(File.read(@resolved_coverage_file))
      unless raw.is_a?(Hash) && raw['coverage'].is_a?(Hash) && raw['meta'].is_a?(Hash)
        raise CoverageDataError,
          'Not a SimpleCov coverage.json document (expected top-level "coverage" and "meta"): ' \
          "#{@resolved_coverage_file}"
      end

      Result.new(
        coverage_map: normalize_coverage_map(raw['coverage']),
        timestamp:    normalize_timestamp(raw['meta']['timestamp'])
      )
    end

    # The JSON formatter marks lines excluded via :nocov: or
    # simplecov:disable directives with the string "ignored". Map them to
    # nil, SimpleCov's "not relevant" value, so excluded lines stay out of
    # the covered and uncovered counts.
    #
    # Only the exact sentinel is translated: any other string is left in
    # place so malformed data is rejected by the line array validation in
    # CoverageLineResolver rather than silently read as a non-executable line.
    private def normalize_coverage_map(coverage)
      coverage.transform_values do |entry|
        lines = entry.is_a?(Hash) ? entry['lines'] : nil
        next entry unless lines.is_a?(Array) && lines.include?(IGNORED_LINE)

        entry.merge('lines' => lines.map { |hits| hits == IGNORED_LINE ? nil : hits })
      end
    end

    # SimpleCov writes an ISO 8601 string. Epoch numbers are accepted too,
    # since third-party formatters that rewrite coverage.json use them.
    private def normalize_timestamp(value)
      case value
      when nil
        @logger.safe_log('Coverage timestamp missing, defaulting to 0. ' \
                         'Time-based staleness checks will be disabled.')
        0
      when Numeric
        value.to_i
      when String
        Time.parse(value).to_i
      else
        @logger.safe_log("Coverage timestamp could not be parsed: #{value.inspect}")
        0
      end
    rescue ArgumentError => e
      @logger.safe_log("Coverage timestamp could not be parsed: #{value.inspect} (#{e.message})")
      0
    end
  end
end
