# frozen_string_literal: true

module CovLoupe
  # Immutable data container for coverage data loaded from a specific coverage file.
  # Holds the normalized coverage map, timestamp, and coverage file path.
  #
  # This class has no awareness of caching - it's managed by ModelDataCache.
  #
  # @attr_reader coverage_map [Hash] Map of absolute file paths to coverage data
  # @attr_reader timestamp [Integer] Latest timestamp from coverage suites
  # @attr_reader coverage_file_path [String] Absolute path to the coverage.json or
  #   .resultset.json file
  ModelData = Data.define(:coverage_map, :timestamp, :coverage_file_path)
end
