# frozen_string_literal: true

require 'pathname'
require_relative 'volume_case_sensitivity'

module CovLoupe
  # Centralized path handling utilities providing consistent normalization,
  # relativization, and absolutization across all components.
  #
  # All path operations in cov-loupe should go through this module to ensure
  # consistent handling of:
  # - Platform differences (Windows backslashes, drive letters)
  # - Case sensitivity (detected per-volume at runtime)
  # - Relative vs absolute path resolution
  #
  # Case sensitivity is derived from the volume containing the given path, not
  # from a global setting. This is important for projects that span multiple
  # volumes (e.g., project on macOS case-insensitive volume, coverage file on a
  # case-sensitive external drive).
  module PathUtils
    # Platform detection - delegates to main CovLoupe module for testability
    def self.windows?
      CovLoupe.windows?
    end

    def self.windows_drive?
      File.expand_path('.').match?(/^[A-Za-z]:/)
    end

    # Normalizes a path by handling:
    # 1. Slash normalization (Windows backslashes -> forward slashes)
    # 2. Case normalization (case-insensitive volumes)
    # 3. Path cleaning (removing ., .., redundant separators)
    #
    # @param path [String, Pathname] path to normalize
    # @param options [Hash] normalization options
    # @option options [Boolean] :normalize_case (true on case-insensitive volumes)
    # @option options [String] :root (nil) root directory for determining volume case-sensitivity
    # @return [String] normalized path
    def self.normalize(path, options = {})
      return path if path.nil? || path.empty?

      result = path.to_s

      # Always normalize slashes on Windows (Pathname#cleanpath does this anyway)
      result = result.tr('\\', '/') if windows?

      # Handle case normalization for case-insensitive volumes
      # If root is provided, derive case-sensitivity from root's volume
      root = options[:root]
      begin
        default_normalize_case = if root
          !VolumeCaseSensitivity.volume_case_sensitive?(root)
        else
          !VolumeCaseSensitivity.volume_case_sensitive?
        end
      rescue SystemCallError, IOError
        # If we can't detect case sensitivity, assume case-insensitive to be conservative
        default_normalize_case = true
      end
      if options.fetch(:normalize_case, default_normalize_case)
        result = result.downcase
      end

      # Clean path components
      Pathname.new(result).cleanpath.to_s
    end

    # Expands a path to absolute form, optionally relative to a base directory
    #
    # @param path [String] path to expand
    # @param base [String, nil] base directory (defaults to current working directory)
    # @return [String] absolute path
    def self.expand(path, base = nil)
      return path if path.nil? || path.empty?

      # On Windows, only bypass File.expand_path if path already has a drive letter.
      # Paths like "/foo" are considered absolute by absolute? but need File.expand_path
      # to acquire the current drive letter (e.g., "C:/foo").
      if absolute?(path) && (!windows? || path.match?(/^[A-Za-z]:/))
        # Use Pathname#cleanpath to preserve case on Windows, as File.expand_path
        # can sometimes canonicalize case for existing files.
        Pathname.new(path).cleanpath.to_s
      else
        base ? File.expand_path(path, base) : File.expand_path(path)
      end
    end

    # Converts an absolute path to a path relative to the given root
    #
    # @param path [String] absolute path to relativize
    # @param root [String] root directory for relativization
    # @return [String] relative path or original path if conversion fails
    def self.relativize(path, root)
      return path if path.nil? || path.empty? || root.nil? || root.empty?

      # Only expand relative paths against root; absolute paths expand without base
      abs_path = absolute?(path) ? expand(path) : expand(path, root)
      abs_root = expand(root)

      # Check if path is within root using normalized comparison
      # Derive case-sensitivity from root's volume for accurate cross-volume handling
      return path unless normalized_start_with?(abs_path, abs_root, root: abs_root)

      # Normalize paths before relative_path_from so Pathname can compute the relative path
      # regardless of mixed separators or case differences. Case-sensitivity is derived from
      # root's volume.
      case_sensitive = begin
        VolumeCaseSensitivity.volume_case_sensitive?(abs_root)
      rescue SystemCallError, IOError
        # If we can't detect case sensitivity, assume case-insensitive to be conservative
        false
      end
      normalized_path = normalize(abs_path, normalize_case: !case_sensitive, root: abs_root)
      normalized_root = normalize(abs_root, normalize_case: !case_sensitive, root: abs_root)

      relative = Pathname.new(normalized_path)
        .relative_path_from(Pathname.new(normalized_root))
        .to_s

      # Pathname computes the relative path from the normalized strings, which may all be
      # lowercase on case-insensitive volumes. Rebuild the result from abs_path so reports
      # keep the casing the user actually sees on disk.
      if !case_sensitive && relative != '.'
        preserve_original_casing(relative, abs_path, abs_root)
      else
        relative
      end
    rescue ArgumentError
      # Path is on a different drive or cannot be made relative
      path
    end

    # Checks if a path is absolute
    #
    # @param path [String] path to check
    # @return [Boolean] true if path is absolute
    def self.absolute?(path)
      return false if path.nil? || path.empty?

      # Check for Windows drive paths (C:/, D:/, etc.)
      return true if path.match?(%r{^[A-Za-z]:[/\\]})

      Pathname.new(path).absolute?
    end

    # Checks if a path is relative
    #
    # @param path [String] path to check
    # @return [Boolean] true if path is relative
    def self.relative?(path)
      !absolute?(path)
    end

    # Checks if a path is within a given root directory
    #
    # @param path [String] path to check
    # @param root [String] root directory
    # @return [Boolean] true if path is within root
    def self.within_root?(path, root)
      return false if path.nil? || root.nil?

      abs_path = expand(path)
      abs_root = expand(root)

      normalized_start_with?(abs_path, abs_root, root: abs_root)
    end

    # Extracts basename from a path, handling normalization
    #
    # @param path [String] path to extract basename from
    # @param options [Hash] options passed to normalize
    # @return [String] basename
    def self.basename(path, options = {})
      return '' if path.nil? || path.empty?

      normalize(path, options).split('/').last
    end

    # Joins path components using platform-appropriate separators
    #
    # @param components [Array<String>] path components
    # @return [String] joined path
    def self.join(*components)
      File.join(*components)
    end

    # Detects whether the volume at the given path is case-sensitive.
    # Delegates to VolumeCaseSensitivity module for implementation.
    #
    # @param path [String, nil] directory path to test (defaults to current directory)
    # @return [Boolean] true if case-sensitive, false if case-insensitive or on error
    def self.volume_case_sensitive?(path = nil)
      VolumeCaseSensitivity.volume_case_sensitive?(path)
    end

    # Clears the volume case sensitivity cache (useful for testing)
    #
    # @return [void]
    def self.clear_volume_case_sensitivity_cache
      VolumeCaseSensitivity.clear_cache
    end

    # Returns root path with trailing separator for prefix matching
    #
    # @param root [String] root path
    # @return [String] root with trailing separator
    def self.root_prefix(root)
      return '' if root.nil? || root.empty?

      root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
    end

    # Preserves original casing from the source path when creating a relative path
    #
    # @param relative_path [String] normalized relative path
    # @param source_path [String] original source path with original casing
    # @param root_path [String] root path
    # @return [String] relative path with original casing preserved
    def self.preserve_original_casing(relative_path, source_path, root_path)
      # Split paths into components
      relative_components = relative_path.split('/')
      source_components = normalize(source_path, normalize_case: false, root: root_path).split('/')
      root_components = normalize(root_path, normalize_case: false, root: root_path).split('/')

      # Skip root components to get to the relative part
      relative_start_index = root_components.length

      # relative_path and the tail of source_path have the same component count because
      # relative_path was derived from source_path relative to root_path just above.
      # Map each normalized component back to its original casing
      original_components = relative_components.map.with_index do |_component, index|
        source_index = relative_start_index + index
        source_components[source_index] || relative_components[index]
      end

      original_components.join('/')
    end

    # Checks if a path starts with a prefix using normalized comparison
    # to handle case-insensitive volumes and mixed separators
    #
    # @param path [String] path to check
    # @param prefix [String] prefix to match against
    # @param root [String, nil] root directory for determining volume case-sensitivity
    # @return [Boolean] true if path starts with prefix (after normalization)
    def self.normalized_start_with?(path, prefix, root: nil)
      return false if path.nil? || prefix.nil? || prefix.empty?

      # Normalize both paths for comparison (case + separators)
      # If root is provided, derive case-sensitivity from root's volume
      case_sensitive = begin
        if root
          VolumeCaseSensitivity.volume_case_sensitive?(root)
        else
          VolumeCaseSensitivity.volume_case_sensitive?
        end
      rescue SystemCallError, IOError
        # If we can't detect case sensitivity, assume case-insensitive to be conservative
        false
      end
      normalized_path = normalize(path, normalize_case: !case_sensitive, root: root)
      normalized_prefix = normalize(prefix, normalize_case: !case_sensitive, root: root)

      # Check if normalized path starts with normalized prefix
      # AND ensure we have proper path boundary (either exact match or followed by separator)
      return false unless normalized_path.start_with?(normalized_prefix)

      # If exact match, return true
      return true if normalized_path == normalized_prefix

      # Otherwise, ensure character after prefix is a path separator
      # (normalize converts all backslashes to forward slashes, so only check for /)
      prefix_length = normalized_prefix.length
      normalized_path[prefix_length] == '/'
    end
  end
end
