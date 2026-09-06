# frozen_string_literal: true

require 'json'

require_relative '../errors/errors'
require_relative 'resultset_loader'
require_relative 'timestamp_normalization'

module CovLoupe
  # Reads and parses a SimpleCov coverage.json file, the documented output
  # of SimpleCov's JSON formatter (written alongside the HTML report by
  # default from SimpleCov 1.0.0 on, and described by a versioned JSON
  # schema in the simplecov repository).
  #
  # Unlike .resultset.json, which is SimpleCov's internal merge cache keyed
  # by test suite, coverage.json contains a single already-merged coverage
  # map, so no suite merging is needed. File keys are project-relative from
  # SimpleCov 1.0.0 on (absolute in earlier versions); CoverageRepository
  # normalizes either form against the project root.
  #
  # The timestamp comes from meta.timestamp (ISO 8601) and is normalized to
  # integer epoch seconds; the suite name comes from meta.command_name.
  class CoverageJsonLoader
    include TimestampNormalization

    # Sentinel the JSON formatter writes for lines excluded from coverage.
    IGNORED_LINE = 'ignored'

    # Structural detection for routing in CoverageFileLoader: coverage.json
    # is a document with a "coverage" map plus "meta", while a resultset is
    # keyed by suite name with nested "coverage" entries.
    def self.coverage_json?(raw)
      raw.is_a?(Hash) && raw['coverage'].is_a?(Hash) && raw['meta'].is_a?(Hash)
    end

    def self.load(path:, logger: nil)
      logger ||= CovLoupe.logger
      new(path: path, logger: logger).load
    end

    # Load from JSON that has already been parsed (used by
    # CoverageFileLoader, which reads the file once to detect its format).
    def self.load_parsed(raw, path:, logger: nil)
      logger ||= CovLoupe.logger
      new(path: path, logger: logger).load(raw)
    end

    def initialize(path:, logger:)
      @path = path
      @logger = logger
    end

    def load(raw = nil)
      raw ||= JSON.parse(File.read(@path))
      unless self.class.coverage_json?(raw)
        raise CoverageDataError,
          "Not a SimpleCov JSON formatter document (expected top-level \"coverage\" and \"meta\"): #{@path}"
      end

      meta = raw['meta']
      ResultsetLoader::Result.new(
        coverage_map: normalize_coverage_map(raw['coverage']),
        timestamp:    normalize_coverage_timestamp(meta['timestamp'], nil),
        suite_names:  [meta['command_name']].compact
      )
    end

    # The JSON formatter marks lines excluded via :nocov: or
    # simplecov:disable directives with the string "ignored" (raw
    # resultsets never contain these). Map them to nil, SimpleCov's
    # "not relevant" value, so excluded lines stay out of the covered
    # and uncovered counts. Present in every formatter era, 0.18
    # through 1.0.
    #
    # Only the exact sentinel is translated: any other string is left
    # in place so malformed data is rejected by the line array
    # validation in CoverageLineResolver rather than silently read as a
    # non-executable line.
    private def normalize_coverage_map(coverage)
      coverage.transform_values do |entry|
        lines = entry.is_a?(Hash) ? entry['lines'] : nil
        next entry unless lines.is_a?(Array) && lines.include?(IGNORED_LINE)

        entry.merge('lines' => lines.map { |hits| hits == IGNORED_LINE ? nil : hits })
      end
    end
  end
end
