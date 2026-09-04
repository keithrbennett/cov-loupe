# frozen_string_literal: true

require 'digest'
require_relative 'model_data'
require_relative '../repositories/coverage_repository'

module CovLoupe
  # Thread-safe singleton cache for ModelData instances.
  # Entries are keyed by [coverage_file_path, root] and automatically invalidated when the file changes.
  #
  # Cache invalidation uses a two-layer check:
  #   1. Signature: file mtime + size + inode (cheap, no file read)
  #   2. Digest: MD5 hash of file contents (catches same-mtime edits on coarse-grained filesystems)
  #
  # Both must match for a cache hit. If either differs, fresh data is loaded.
  #
  # The cache key includes both coverage_file_path and root because path normalization and
  # case-sensitivity detection depend on the root directory. Two models with the same
  # coverage file but different roots may have different normalized coverage maps.
  #
  # Why a singleton? CoverageModel instances are lightweight (created per request in MCP mode),
  # but loading and normalizing the coverage file is expensive. The singleton cache ensures that
  # repeated requests for the same coverage file reuse the parsed data until the file changes.
  class ModelDataCache
    # Mutex for thread-safe singleton initialization.
    # Using a constant ensures it cannot be reset, avoiding race conditions in JRuby.
    INSTANCE_MUTEX = Mutex.new

    def initialize
      @entries = {}
      @mutex = Mutex.new
    end

    # Returns the singleton instance with thread-safe initialization
    def self.instance
      INSTANCE_MUTEX.synchronize do
        @instance ||= new
      end
    end

    # Fetches ModelData for the given coverage file path.
    # Checks signature/digest on every call and reloads if the file has changed.
    #
    # @param coverage_file_path [String] Absolute path to coverage.json or .resultset.json
    # @param root [String] Project root directory for path normalization
    # @param logger [Logger, nil] Logger instance for data loading operations
    # @return [ModelData] The cached or freshly loaded data
    #
    # @note Complexity: O(1) amortized for cache hits. For cache misses, O(n) where n
    #   is the size of the coverage file, plus O(m) for parsing where m is total lines.
    #   File stat and MD5 digest are O(1) relative to file size on most filesystems.
    # @note Thread-safety: Thread-safe. This method uses a Mutex to synchronize access
    #   to the internal cache entries hash. Concurrent calls from multiple threads
    #   are guaranteed to return consistent results without data races.
    def get(coverage_file_path, root:, logger: nil)
      @mutex.synchronize do
        # Cache key must include both coverage_file_path and root because
        # path normalization and case-sensitivity depend on the root
        cache_key = [coverage_file_path, root]
        entry = @entries[cache_key]

        # Signature (mtime/size/inode) is cheap — no file read required. Digest (MD5)
        # is a fallback guard for filesystems with coarse mtime precision where two
        # different writes can land with the same timestamp.
        signature = compute_signature(coverage_file_path)
        digest = compute_digest(coverage_file_path)

        # Both must match: signature catches most changes; digest catches same-mtime edits.
        if entry && signature && digest &&
            entry[:signature] == signature &&
            entry[:digest] == digest
          return entry[:data]
        end

        # Load fresh data using the provided logger
        data = load_data(coverage_file_path, root, logger)

        # Store with signature/digest if we computed them
        if signature && digest
          @entries[cache_key] = {
            data:      data,
            signature: signature,
            digest:    digest,
          }
        end

        data
      end
    end

    # Clears all cached entries (primarily for testing)
    def clear
      @mutex.synchronize { @entries.clear }
    end

    private def load_data(coverage_file_path, root, logger)
      repo = Repositories::CoverageRepository.new(
        root:               root,
        coverage_file_path: coverage_file_path,
        logger:             logger || CovLoupe.logger
      )

      ModelData.new(
        coverage_map:       repo.coverage_map,
        timestamp:          repo.timestamp,
        coverage_file_path: coverage_file_path
      )
    end

    private def compute_signature(coverage_file_path)
      stat = File.stat(coverage_file_path)
      {
        mtime:      stat.mtime,
        mtime_nsec: stat.respond_to?(:mtime_nsec) ? stat.mtime_nsec : stat.mtime.nsec,
        size:       stat.size,
        inode:      stat.respond_to?(:ino) ? stat.ino : nil,
      }.compact
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end

    # Compute a fast digest of the coverage file.
    # Uses MD5 which is fast and sufficient for cache validation
    # (we don't need cryptographic security, just change detection).
    private def compute_digest(coverage_file_path)
      Digest::MD5.file(coverage_file_path).hexdigest
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
