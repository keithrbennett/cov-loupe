# frozen_string_literal: true

require_relative 'path_utils'

module CovLoupe
  # File globbing utilities for filtering coverage data by path patterns.
  #
  # Uses File.fnmatch? for pure string matching (no filesystem access for glob evaluation).
  # Case-insensitive matching is automatically applied on case-insensitive volumes,
  # detected by testing the volume containing the project root (or the path being matched
  # when no root is given).
  module GlobUtils
    GLOB_MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB

    # Returns a lambda that normalizes path separators for the current platform.
    # On Windows, returns a lambda that converts backslashes to forward slashes.
    # On Unix, returns a pass-through lambda.
    # The lambda is memoized so platform detection only happens once.
    # @return [Proc] lambda that takes a string and returns it normalized
    module_function def fn_normalize_path_separators
      @fn_normalize_path_separators ||= if CovLoupe.windows?
        ->(str) { str.tr('\\', '/') }
      else
        ->(str) { str }
      end
    end

    module_function def normalize_patterns(globs)
      Array(globs).compact.map(&:to_s).reject(&:empty?)
    end

    # Converts a pattern to absolute path relative to a root.
    # Handles both relative patterns ("lib/*.rb") and absolute ones ("/tmp/*.rb").
    #
    # @param pattern [String] glob pattern
    # @param root [String] root directory path
    # @return [String] absolute pattern
    module_function def absolutize_pattern(pattern, root)
      File.expand_path(pattern, root)
    end

    # Builds fnmatch flags, adding FNM_CASEFOLD on case-insensitive volumes.
    # Walks up from +path+ to the first existing directory to probe volume properties.
    #
    # @param path [String] absolute path (file or directory) on the volume of interest
    # @return [Integer] flags for File.fnmatch?
    module_function def match_flags(path)
      test_dir = path
      until File.directory?(test_dir)
        parent = File.dirname(test_dir)
        break if parent == test_dir # Reached root (works on Windows and Unix)

        test_dir = parent
      end

      begin
        return GLOB_MATCH_FLAGS if PathUtils.volume_case_sensitive?(test_dir)
      rescue SystemCallError, IOError
        # If we can't detect case sensitivity, assume case-insensitive to be conservative
      end
      GLOB_MATCH_FLAGS | File::FNM_CASEFOLD
    end

    # Tests if a file path matches any of the given absolute glob patterns.
    # Uses File.fnmatch? for pure string matching without filesystem access.
    # Normalizes paths to forward slashes on Windows for cross-platform compatibility.
    # Automatically handles case-insensitive filesystems by detecting volume case-sensitivity.
    #
    # @param abs_path [String] absolute file path to test
    # @param patterns [Array<String>] absolute glob patterns
    # @param flags [Integer, nil] precomputed fnmatch flags; when nil, detected from abs_path's
    #   volume. Callers matching many paths should compute once via {match_flags}.
    # @return [Boolean] true if the path matches at least one pattern
    module_function def matches_any_pattern?(abs_path, patterns, flags: nil)
      normalizer = fn_normalize_path_separators
      normalized_path = normalizer.call(abs_path)
      flags ||= match_flags(abs_path)

      patterns.any? do |pattern|
        normalized_pattern = normalizer.call(pattern)
        File.fnmatch?(normalized_pattern, normalized_path, flags)
      end
    end

    # Filters items where a key contains a file path matching the patterns.
    #
    # @param items [Array<Hash>] items to filter
    # @param patterns [Array<String>] absolute glob patterns
    # @param key [String] key in item hash containing the absolute file path
    # @param root [String, nil] project root; when given, case sensitivity is detected once
    #   from its volume rather than per item
    # @return [Array<Hash>] items whose file path matches at least one pattern
    module_function def filter_by_pattern(items, patterns, key: 'file', root: nil)
      return items if patterns.nil? || patterns.empty?

      flags = root && match_flags(File.expand_path(root))
      items.select { |item| matches_any_pattern?(item[key], patterns, flags: flags) }
    end

    # Filters an array of absolute file paths by glob patterns.
    # Handles normalization and absolutization of patterns internally.
    #
    # @param paths [Array<String>] absolute file paths to filter
    # @param globs [Array<String>, String, nil] glob patterns (can be relative)
    # @param root [String] root directory for resolving relative patterns
    # @return [Array<String>] paths that match at least one pattern (or all if no patterns)
    module_function def filter_paths(paths, globs, root:)
      patterns = normalize_patterns(globs)
      return paths if patterns.empty?

      absolute_patterns = patterns.map { |p| absolutize_pattern(p, root) }
      flags = match_flags(File.expand_path(root))
      paths.select { |path| matches_any_pattern?(path, absolute_patterns, flags: flags) }
    end
  end
end
