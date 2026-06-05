# frozen_string_literal: true

require 'fileutils'

module CovLoupe
  # Handles detection and caching of filesystem volume case sensitivity.
  # Provides thread-safe case sensitivity detection with caching for performance.
  module VolumeCaseSensitivity
    # Mutex for thread-safe cache access
    CACHE_MUTEX = Mutex.new

    class << self
      # Detects whether the volume at the given path is case-sensitive.
      # Prefer using an existing file (via File.identical?) to avoid writing;
      # fall back to a temporary file if no suitable file exists.
      #
      # This method caches results by path to avoid repeated filesystem checks,
      # which can be expensive, especially on network-mounted volumes.
      #
      # @param path [String, nil] directory path to test (defaults to current directory)
      # @return [Boolean] true if case-sensitive, false if case-insensitive or on error
      def volume_case_sensitive?(path = nil)
        require 'securerandom'

        test_path = path ? File.absolute_path(path) : Dir.pwd
        abs_path = File.absolute_path(test_path)

        # Check cache first (thread-safe read)
        cached_value = get_from_cache(abs_path)
        return cached_value unless cached_value.nil?

        # Return false if directory doesn't exist
        return false unless File.directory?(abs_path)

        result = detect_case_sensitivity?(abs_path)

        # Store result in cache (thread-safe write)
        set_in_cache(abs_path, result)

        result
      rescue SystemCallError, IOError
        # Can't detect from filesystem, assume case-insensitive to be conservative
        false
      end

      # Clears the case sensitivity cache (useful for testing)
      #
      # @return [void]
      def clear_cache
        CACHE_MUTEX.synchronize do
          @cache = {}
        end
      end

      # Returns the current cache contents (useful for testing)
      #
      # @return [Hash] cache contents
      def cache
        CACHE_MUTEX.synchronize do
          @cache ||= {}
          @cache.dup
        end
      end

      # Retrieves a value from the cache (thread-safe)
      #
      # @param abs_path [String] absolute path to look up
      # @return [Boolean, nil] cached value or nil if not found
      def get_from_cache(abs_path)
        CACHE_MUTEX.synchronize do
          @cache ||= {}
          @cache[abs_path]
        end
      end

      # Stores a value in the cache (thread-safe)
      #
      # @param abs_path [String] absolute path to cache
      # @param value [Boolean] value to cache
      # @return [void]
      def set_in_cache(abs_path, value)
        CACHE_MUTEX.synchronize do
          @cache ||= {}
          @cache[abs_path] = value
        end
      end

      # Detects case sensitivity for a given directory
      #
      # @param abs_path [String] absolute path to directory
      # @return [Boolean] true if case-sensitive, false if case-insensitive
      def detect_case_sensitivity?(abs_path)
        # Try to use an existing file to avoid filesystem writes
        existing_file = find_existing_file(abs_path)

        if existing_file
          detect_case_sensitive_using_existing_file?(abs_path, existing_file)
        else
          detect_case_sensitive_using_temp_file?(abs_path)
        end
      end

      # Finds an existing file in the directory suitable for case sensitivity testing
      #
      # @param abs_path [String] absolute path to directory
      # @return [String, nil] filename or nil if no suitable file found
      def find_existing_file(abs_path)
        Dir.children(abs_path).find do |name|
          name.match?(/[A-Za-z]/) && File.file?(File.join(abs_path, name))
        end
      end

      # Detects case sensitivity using an existing file in the directory
      #
      # @param abs_path [String] absolute path to directory
      # @param existing_file [String] name of existing file
      # @return [Boolean] true if case-sensitive, false if case-insensitive
      def detect_case_sensitive_using_existing_file?(abs_path, existing_file)
        original = File.join(abs_path, existing_file)
        # tr('A-Za-z', 'a-zA-Z') swaps the case of every letter in the filename
        alternate_name = existing_file.tr('A-Za-z', 'a-zA-Z')
        alternate = File.join(abs_path, alternate_name)

        if File.exist?(alternate)
          # Same file -> case-insensitive, different files -> case-sensitive
          !File.identical?(original, alternate)
        else
          # On a case-insensitive filesystem, File.exist? for the alternate-cased name would
          # resolve to the same inode and return true. Reaching this branch means the filesystem
          # treats the two paths as distinct entries, confirming case-sensitivity.
          true
        end
      end

      # Detects case sensitivity using a temporary test file
      #
      # @param abs_path [String] absolute path to directory
      # @return [Boolean] true if case-sensitive, false if case-insensitive
      def detect_case_sensitive_using_temp_file?(abs_path)
        require 'securerandom'

        # Create a temporary test file with a unique name
        test_file = generate_unique_test_filename(abs_path)

        begin
          FileUtils.touch(test_file)
          variants = [test_file, test_file.upcase, test_file.downcase]
          # Test if exactly one variant exists (case-sensitive) vs all exist (case-insensitive)
          variants.one? { |variant| File.exist?(variant) }
        ensure
          # Clean up all potential variants
          [test_file, test_file.upcase, test_file.downcase].each do |variant|
            FileUtils.rm_f(variant)
          end
        end
      end

      # Generates a unique test filename that doesn't conflict with existing files
      #
      # @param abs_path [String] absolute path to directory
      # @return [String] unique filename path
      def generate_unique_test_filename(abs_path)
        require 'securerandom'

        test_file = nil
        while test_file.nil?
          candidate = File.join(abs_path, "CovLoupe_CaseSensitivity_Test_#{SecureRandom.hex(16)}.tmp")
          variants = [candidate, candidate.upcase, candidate.downcase]
          test_file = candidate if variants.none? { |v| File.exist?(v) }
        end
        test_file
      end
    end
  end
end
