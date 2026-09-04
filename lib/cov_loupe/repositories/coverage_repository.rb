# frozen_string_literal: true

require 'json'
require_relative '../deprecation'
require_relative '../resolvers/resolver_helpers'
require_relative '../loaders/coverage_file_loader'
require_relative '../errors/errors'
require_relative '../paths/path_utils'

module CovLoupe
  module Repositories
    # CoverageRepository handles the discovery, loading, and normalization of SimpleCov
    # coverage data. It decouples data access concerns from the domain logic in CoverageModel.
    #
    # Its primary responsibilities are:
    # 1. Locating the coverage file (coverage.json or .resultset.json) using ResolverHelpers.
    # 2. Loading and parsing the JSON data using CoverageFileLoader, which detects the format
    #    and routes to the right loader (handling resultset suite merging if needed).
    # 3. Normalizing all coverage map keys to absolute paths relative to the project root.
    #
    # @attr_reader coverage_map [Hash] A map of absolute file paths to coverage data.
    # @attr_reader timestamp [Integer] The latest timestamp from the loaded coverage suites.
    # @attr_reader coverage_file_path [String] The resolved absolute path to the coverage file.
    class CoverageRepository
      attr_reader :coverage_map, :timestamp, :coverage_file_path

      def initialize(root:, coverage_file_path: nil, logger: nil)
        @root = root
        @logger = logger || CovLoupe.logger

        begin
          # 1. Locate the file
          @coverage_file_path = resolve_coverage_file_path(coverage_file_path)

          # 2. Load the data
          loaded_data = load_data

          # 3. Detect volume case sensitivity from project root
          @volume_case_sensitive = detect_volume_case_sensitivity

          # 4. Normalize keys to absolute paths
          @coverage_map = normalize_paths(loaded_data.coverage_map)
          @timestamp = loaded_data.timestamp
        rescue CovLoupe::Error
          raise # Re-raise our own errors as-is
        rescue => e
          raise ErrorHandler.new.convert_standard_error(e, context: :coverage_loading)
        end
      end

      # Deprecated reader for coverage_file_path. Removed in v7.0.0.
      def resultset_path
        Deprecation.warn('CoverageRepository#resultset_path', '#coverage_file_path')
        @coverage_file_path
      end

      private def resolve_coverage_file_path(path_arg)
        Resolvers::ResolverHelpers.find_coverage_file(@root, coverage_file: path_arg)
      end

      private def load_data
        CoverageFileLoader.load(path: @coverage_file_path, logger: @logger)
      end

      # Detects volume case sensitivity from the project root directory.
      # Uses @root because coverage map keys are paths to source files in the project.
      #
      # Falls back to assuming case-insensitive if @root doesn't exist (test scenarios)
      # or isn't accessible. This conservative fallback catches more potential collisions.
      #
      # @return [Boolean] true if volume is case-sensitive
      private def detect_volume_case_sensitivity
        return false unless File.directory?(@root)

        PathUtils.volume_case_sensitive?(@root)
      rescue SystemCallError, IOError
        # Can't detect from filesystem, assume case-insensitive to be conservative
        false
      end

      # Normalizes all coverage map keys to absolute paths and detects collisions.
      #
      # Two-pass algorithm:
      #   Pass 1: Expand each key to an absolute path, then normalize case (if volume
      #           is case-insensitive) for collision detection. Store using the expanded
      #           (case-preserved) key for correct display in reports.
      #   Pass 2: Report any normalized key with multiple original keys as a collision,
      #           since this would cause silent data loss (last-write-wins).
      #
      # @param map [Hash] Original coverage map with potentially relative/mixed keys
      # @return [Hash] Normalized coverage map with absolute path keys (preserving original case)
      # @raise [CoverageDataError] If duplicate keys normalize to the same path
      private def normalize_paths(map)
        return {} unless map

        result = {}
        # Track which original keys map to each normalized key to detect collisions
        # Example: { "/abs/path/lib/foo.rb" => ["lib/foo.rb", "/abs/path/lib/foo.rb"] }
        provided_paths_by_normalized_path = Hash.new { |h, k| h[k] = [] }
        # Track the expanded (but not case-normalized) key for storage
        # Example: { "/abs/path/lib/foo.rb" => "/full/path/lib/foo.rb" }
        expanded_by_normalized = {}

        # First pass: normalize all keys and track the mapping
        map.each do |original_key, value|
          # Expand to absolute path first
          expanded_key = PathUtils.expand(original_key, @root)

          # Then apply case normalization for collision detection only
          # Pass root to ensure case-sensitivity is derived from root's volume
          normalized_key = PathUtils.normalize(
            expanded_key,
            normalize_case: !@volume_case_sensitive,
            root:           @root
          )

          provided_paths_by_normalized_path[normalized_key] << original_key
          # Store using expanded key (preserves original case) for display purposes
          expanded_by_normalized[normalized_key] ||= expanded_key
          result[expanded_by_normalized[normalized_key]] = value
        end

        # Second pass: detect collisions (any normalized key with multiple original keys)
        collisions = provided_paths_by_normalized_path.select do |_norm_key, orig_keys|
          orig_keys.size > 1
        end

        collisions.empty? ? result : raise_collision_error(collisions, expanded_by_normalized)
      end

      # Raises a CoverageDataError with details about path normalization collisions.
      #
      # Formats collision data as parseable JSON with each collision on one line:
      #   {
      #     "/full/path/lib/foo.rb": ["lib/foo.rb", "/full/path/lib/foo.rb"],
      #     "/full/path/lib/bar.rb": ["lib/bar.rb", "/full/path/lib/bar.rb"]
      #   }
      #
      # @param collisions [Hash] Map of normalized paths to arrays of original keys
      # @param expanded_by_normalized [Hash] Map of normalized paths to case-preserved expanded paths
      # @raise [CoverageDataError] Always raises with formatted collision details
      private def raise_collision_error(collisions, expanded_by_normalized)
        json_lines = collisions.map do |norm_key, orig_keys|
          # Use the case-preserved expanded key instead of the normalized key
          expanded_key = expanded_by_normalized[norm_key]
          "  #{JSON.generate(expanded_key)}: #{JSON.generate(orig_keys)}"
        end
        details = "{\n#{json_lines.join(",\n")}\n}"

        raise CoverageDataError, 'Duplicate paths detected after normalization.' \
          "The following keys normalize to the same path:\n#{details}"
      end
    end
  end
end
