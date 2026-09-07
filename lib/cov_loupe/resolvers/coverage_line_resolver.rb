# frozen_string_literal: true

require_relative '../paths/path_utils'

module CovLoupe
  module Resolvers
    # Finds a SimpleCov line coverage array for a given file path.
    #
    # Resolution strategy (in order):
    # 1. Exact match on the normalized input path
    # 2. Match after stripping the project root prefix (handles the project-relative keys SimpleCov writes)
    #
    # On case-insensitive volumes, all comparisons are case-normalized to avoid
    # false negatives. If multiple coverage entries normalize to the same path,
    # an ambiguity error is raised to prevent silent data corruption.
    #
    # This resolver is string-based only — it does not touch the filesystem.
    class CoverageLineResolver
      # @param cov_data [Hash] coverage data map keyed by file path
      # @param root [String, nil] project root used for path stripping
      # @param volume_case_sensitive [Boolean] whether the volume is case-sensitive
      def initialize(cov_data, root:, volume_case_sensitive:)
        @cov_data = cov_data
        @root = root
        @normalize_case = !volume_case_sensitive
      end

      # Resolve coverage lines for a file path, trying fallbacks before raising.
      # @param file_abs [String] absolute file path to resolve
      # @return [Array<Integer, nil>] SimpleCov-style line coverage array
      def lookup_lines(file_abs)
        # Normalize the input path first to handle platform-specific differences
        normalized_path = normalize_path(file_abs)

        # First try exact match
        direct_match = find_direct_match(normalized_path)
        return direct_match if direct_match

        # Then try without current working directory prefix
        stripped_match = find_stripped_match(normalized_path)
        return stripped_match if stripped_match

        raise_not_found_error(file_abs)
      end

      attr_reader :cov_data

      private def find_direct_match(file_abs)
        fetch_lines_for_path(file_abs)
      end

      # Try matching a path after removing the root prefix.
      private def find_stripped_match(file_abs)
        return unless @root

        normalized_file = normalize_path(file_abs)
        return unless normalized_file.start_with?(normalized_root_with_slash)

        relative_path = normalized_file[(normalized_root.length + 1)..]
        fetch_lines_for_path(relative_path)
      end

      # Fetch lines for a path, resolving normalized separators when needed.
      private def fetch_lines_for_path(path)
        key = resolve_key(path)
        return unless key

        entry = cov_data[key]
        lines = lines_from_entry(entry)
        return lines if lines

        raise CorruptCoverageDataError, "Entry for #{path} has no valid lines"
      end

      private def resolution_root
        @resolution_root ||= @root
      end

      private def normalized_root
        @normalized_root ||= normalize_path(resolution_root)
      end

      private def normalized_root_with_slash
        return unless normalized_root

        @normalized_root_with_slash ||= "#{normalized_root}/"
      end

      # Resolve the coverage key that matches a path (including normalized variants).
      private def resolve_key(path)
        normalized = normalize_path(path)
        match_keys = cov_data.keys.select { |key| normalize_path(key) == normalized }

        return if match_keys.empty?

        # Fast path: the original path is a key and it's the only normalized match.
        # Return it directly without going through match_keys.first so callers get
        # back the exact key they supplied rather than a case-normalized variant.
        return path if cov_data.key?(path) && match_keys.length == 1

        # If multiple matches, raise ambiguity error
        if match_keys.length > 1
          raise FileError, "Multiple coverage entries match path #{path}: #{match_keys.join(', ')}"
        end

        # Single match found, return it
        match_keys.first
      end

      # Normalize a path using centralized PathUtils
      private def normalize_path(path)
        PathUtils.normalize(path, normalize_case: @normalize_case)
      end

      private def raise_not_found_error(file_abs)
        raise FileError, "No coverage entry found for #{normalize_path(file_abs)}"
      end

      # Entry may store exact line coverage.
      #
      # Validates that the entry contains a properly-formed lines array
      # with only Integer or nil elements.
      #
      # @raise [CoverageDataError] if lines array contains invalid elements
      # @return [Array<Integer, nil>, nil] validated lines array or nil if entry lacks lines
      private def lines_from_entry(entry)
        return unless entry.is_a?(Hash)

        lines = entry['lines']
        return nil unless lines.is_a?(Array)

        # Validate all elements are Integer or nil
        invalid_elements = lines.reject { |v| v.nil? || v.is_a?(Integer) }
        unless invalid_elements.empty?
          raise CoverageDataError,
            "Invalid coverage line array: contains non-integer elements: #{invalid_elements.inspect}"
        end

        lines
      end
    end
  end
end
