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
  #
  # @api private
  class CoverageJsonLoader
    Result = Struct.new(:coverage_map, :timestamp)

    # Sentinel the JSON formatter writes for lines excluded from coverage.
    IGNORED_LINE = 'ignored'

    # Major version of meta.schema_version (the coverage.json format) that this loader reads.
    SUPPORTED_FORMAT_MAJOR = '1'

    def self.load(resolved_coverage_file:, logger: nil)
      logger ||= CovLoupe.logger
      new(resolved_coverage_file: resolved_coverage_file, logger: logger).load
    end

    def initialize(resolved_coverage_file:, logger:)
      @resolved_coverage_file = resolved_coverage_file
      @logger = logger
    end

    def load
      # JSON is always UTF-8. 'UTF-8:UTF-8' reads it as UTF-8 and keeps it UTF-8; otherwise a
      # non-ASCII path is tagged with the locale's encoding, or transcoded to
      # Encoding.default_internal when that is set, and fails to load or is misread.
      raw = JSON.parse(File.read(@resolved_coverage_file, encoding: 'UTF-8:UTF-8'))
      unless raw.is_a?(Hash) && raw['coverage'].is_a?(Hash) && raw['meta'].is_a?(Hash)
        raise CoverageDataError,
          'Not a SimpleCov coverage.json document (expected top-level "coverage" and "meta"): ' \
          "#{@resolved_coverage_file}"
      end
      validate_format_version(raw['meta'])

      Result.new(
        coverage_map: normalize_coverage_map(raw['coverage']),
        timestamp:    normalize_timestamp(raw['meta']['timestamp'])
      )
    end

    # meta.schema_version is the version of SimpleCov's coverage.json format
    # (e.g. "1.0"), not the SimpleCov gem version. Any 1.x is accepted; a
    # missing value or another major version means a layout cov-loupe may not
    # understand, so fail with a clear message instead of misreading the data.
    private def validate_format_version(meta)
      version = meta['schema_version']
      return if version.is_a?(String) && version.split('.').first == SUPPORTED_FORMAT_MAJOR

      # Shown as a separate field: a gem version is not a format version, and
      # pre-1.0 JSON formatter output carries simplecov_version but no schema_version.
      simplecov_version = meta['simplecov_version']
      found = "meta.schema_version: #{version.inspect}"
      found += "; meta.simplecov_version: #{simplecov_version.inspect}" if simplecov_version
      raise CoverageDataError,
        "Unsupported coverage.json format (#{found}) in #{@resolved_coverage_file}; " \
        'cov-loupe requires format 1.x (written by SimpleCov 1.0 and later)'
    end

    # The JSON formatter marks lines that SimpleCov excluded (via nocov blocks
    # or disable/enable directive comments) with the string "ignored". Map
    # them to nil, SimpleCov's "not relevant" value, so excluded lines stay out of
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
