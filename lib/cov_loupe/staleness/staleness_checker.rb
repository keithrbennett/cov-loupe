# frozen_string_literal: true

require 'time'
require 'pathname'
require 'set' # rubocop:disable Lint/RedundantRequireStatement -- Ruby >= 3.4 requires explicit require for set; RuboCop targets 3.2
require_relative '../errors/errors'
require_relative '../resolvers/resolver_helpers'

module CovLoupe
  # Lightweight service object to check staleness of coverage vs. sources.
  #
  # Staleness detection operates at two levels:
  #   - File level: checks if a single source file is newer than the coverage timestamp
  #     or has a different line count than the coverage array
  #   - Project level: scans all tracked files for newer/missing/deleted/mismatched files
  #
  # Modes:
  #   - :off   → compute staleness but never raise (used for status reporting)
  #   - :error → raise CoverageDataStaleError or CoverageDataProjectStaleError on issues
  #
  # Staleness categories (mutually exclusive per file):
  #   - 'ok'             → file is fresh and line counts match
  #   - 'missing'        → source file deleted since coverage was recorded
  #   - 'newer'          → source mtime exceeds coverage timestamp (only when no length mismatch)
  #   - 'length_mismatch'→ source line count differs from coverage array length
  #   - 'error'          → file could not be read (permissions, I/O)
  class StalenessChecker
    MODES = %i[off error].freeze

    def initialize(root:, coverage_file:, mode: :off, tracked_globs: nil, timestamp: nil)
      @root = File.expand_path(root || '.')
      @coverage_file = coverage_file
      @mode = (mode || :off).to_sym
      @tracked_globs = tracked_globs
      @cov_timestamp = timestamp
      @coverage_file_path = nil
    end

    def off?
      @mode == :off
    end

    # Raise CoverageDataStaleError if stale (only in error mode)
    def check_file!(file_abs, coverage_lines)
      return if off?

      d = compute_file_staleness_details(file_abs, coverage_lines)

      # Raise FileError if there was a read error
      if d[:read_error]
        raise FileError, "Error reading file: #{rel(file_abs)}"
      end

      # For single-file checks, missing files with recorded coverage count as stale
      # via length mismatch; project-level checks also handle deleted files explicitly.
      if d[:newer] || d[:len_mismatch]
        raise CoverageDataStaleError.new(
          nil,
          nil,
          file_path:          rel(file_abs),
          file_mtime:         d[:file_mtime],
          cov_timestamp:      d[:coverage_timestamp],
          src_len:            d[:src_len],
          cov_len:            d[:cov_len],
          coverage_file_path: coverage_file_path
        )
      end
    end

    # Compute the staleness status for a specific file relative to coverage.
    # Ignores mode and never raises. Returns a String:
    # - 'ok' - file is not stale (fresh)
    # - 'missing' - the file is missing/deleted
    # - 'newer' - the file mtime is newer than the coverage timestamp
    # - 'length_mismatch' - the source line count differs from coverage lines array length
    # - 'error' - the file cannot be read due to permission or I/O errors
    def file_staleness_status(file_abs, coverage_lines)
      d = compute_file_staleness_details(file_abs, coverage_lines)
      return 'error' if d[:read_error]
      return 'missing' unless d[:exists]
      return 'newer' if d[:newer]
      return 'length_mismatch' if d[:len_mismatch]

      'ok'
    end

    # Compute and return project staleness details (newer, missing, deleted files).
    # If in error mode, raises CoverageDataProjectStaleError when issues are found.
    # Returns a hash { newer_files: [], missing_files: [], deleted_files: [], unreadable_files: [] }
    #
    # Does not check line counts. Use check_project_with_lines! for full staleness detection.
    def check_project!(coverage_map)
      ts = coverage_timestamp
      coverage_files = coverage_map.keys

      newer, deleted, unreadable = compute_newer_and_deleted_files(coverage_files, ts)
      missing = compute_missing_files(coverage_files)

      staleness_details = {
        newer_files:      newer,
        missing_files:    missing,
        deleted_files:    deleted,
        unreadable_files: unreadable,
        timestamp_status: ts.to_i > 0 ? 'ok' : 'missing',
      }

      if @mode == :error && (newer.any? || missing.any? || deleted.any? || unreadable.any?)
        raise CoverageDataProjectStaleError.new(
          nil,
          nil,
          cov_timestamp:      ts,
          newer_files:        newer,
          missing_files:      missing,
          deleted_files:      deleted,
          unreadable_files:   unreadable,
          coverage_file_path: coverage_file_path
        )
      end

      staleness_details
    end

    # Compute and return project staleness details including line-count mismatches.
    # If in error mode, raises CoverageDataProjectStaleError when issues are found.
    # Returns a hash with newer/missing/deleted/mismatched/unreadable files and per-file statuses.
    #
    # Deduplication: files that are both "newer" AND have a length mismatch are reported
    # only as "length_mismatch" (the more specific diagnosis). This prevents a file from
    # appearing in both the newer_files and length_mismatch_files lists.
    def check_project_with_lines!(coverage_lines_by_path, coverage_files:)
      coverage_lines_by_path ||= {}
      ts = coverage_timestamp

      newer, deleted, unreadable = compute_newer_and_deleted_files(coverage_files, ts)
      missing = compute_missing_files(coverage_files)

      file_statuses = {}
      length_mismatch = []

      coverage_lines_by_path.each do |abs_path, coverage_lines|
        details = compute_file_staleness_details(abs_path, coverage_lines)
        status = if details[:read_error]
          'error'
        elsif !details[:exists]
          'missing'
        elsif details[:newer]
          'newer'
        elsif details[:len_mismatch]
          'length_mismatch'
        else
          'ok'
        end
        file_statuses[abs_path] = status
        unreadable << rel(abs_path) if details[:read_error]
        length_mismatch << rel(abs_path) if details[:len_mismatch] && details[:exists]
      end

      # A file can be both newer than the coverage timestamp and otherwise broken (for
      # example unreadable or with a different line count). Keep the more actionable
      # per-file diagnosis and suppress the broader "newer" label to avoid duplicates.
      newer -= length_mismatch
      newer -= unreadable

      staleness_details = {
        newer_files:           newer,
        missing_files:         missing,
        deleted_files:         deleted,
        length_mismatch_files: length_mismatch,
        unreadable_files:      unreadable,
        file_statuses:         file_statuses,
        timestamp_status:      ts.to_i > 0 ? 'ok' : 'missing',
      }

      if @mode == :error && [newer, missing, deleted, length_mismatch, unreadable].any?(&:any?)
        raise CoverageDataProjectStaleError.new(
          nil,
          nil,
          cov_timestamp:         ts,
          newer_files:           newer,
          missing_files:         missing,
          deleted_files:         deleted,
          length_mismatch_files: length_mismatch,
          unreadable_files:      unreadable,
          coverage_file_path:    coverage_file_path
        )
      end

      staleness_details
    end

    private def compute_newer_and_deleted_files(coverage_files, timestamp)
      existing = []
      deleted_abs = []
      unreadable_abs = []

      coverage_files.each do |abs|
        if File.file?(abs)
          existing << abs
        else
          deleted_abs << abs
        end
      rescue SystemCallError, IOError
        # Permission denied or other filesystem errors
        unreadable_abs << abs
      end

      newer = []
      # If timestamp is missing/0, skip newer checks
      check_newer = timestamp.to_i > 0

      existing.each do |abs|
        newer << rel(abs) if check_newer && File.mtime(abs).to_i > timestamp.to_i
      rescue SystemCallError, IOError
        # Permission denied or other filesystem errors reading mtime
        unreadable_abs << abs
      end

      deleted = deleted_abs.map { |abs| rel(abs) }
      unreadable = unreadable_abs.map { |abs| rel(abs) }

      [newer, deleted, unreadable]
    end

    # Identifies tracked files that are missing from coverage.
    # Returns array of relative paths for files matched by tracked_globs but not in coverage.
    private def compute_missing_files(coverage_files)
      return [] unless @tracked_globs && Array(@tracked_globs).any?

      patterns = Array(@tracked_globs).map { |g| File.expand_path(g, @root) }
      tracked = patterns
        .flat_map { |p| Dir.glob(p, File::FNM_EXTGLOB | File::FNM_PATHNAME) }
        .select { |p| File.file?(p) }

      covered_set = coverage_files.to_set
      tracked.reject { |abs| covered_set.include?(abs) }.map { |abs| rel(abs) }
    end

    private def coverage_timestamp
      @cov_timestamp || 0
    end

    private def coverage_file_path
      # Only used for error message context; if the path can't be resolved,
      # nil omits it from the message rather than raising a secondary error.
      @coverage_file_path ||=
        Resolvers::ResolverHelpers.find_coverage_file(@root, coverage_file: @coverage_file)
    rescue
      nil
    end

    private def safe_count_lines(path)
      return 0 unless File.file?(path)

      # Count newlines to match SimpleCov's line counting (not File.foreach which counts iterations)
      File.read(path).count("\n")
    rescue SystemCallError, IOError
      :read_error
    end

    private def safe_file_state(path)
      exists = false
      file_mtime = nil
      read_error = false

      begin
        exists = File.file?(path)
      rescue SystemCallError, IOError
        return [false, nil, true]
      end

      return [false, nil, false] unless exists

      begin
        file_mtime = File.mtime(path)
      rescue SystemCallError, IOError
        read_error = true
      end

      [exists, file_mtime, read_error]
    end

    private def rel(path)
      # Handle relative vs absolute path mismatches that cause ArgumentError
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
    rescue ArgumentError
      # Path is outside the project root or has a different prefix type, fall back to absolute path
      path.to_s
    end

    # Centralized computation of staleness-related details for a single file.
    # Returns a Hash with keys:
    #  :exists, :file_mtime, :coverage_timestamp, :cov_len, :src_len, :newer, :len_mismatch, :read_error
    private def compute_file_staleness_details(file_abs, coverage_lines)
      coverage_ts = coverage_timestamp

      exists, file_mtime, read_error = safe_file_state(file_abs)

      cov_len = coverage_lines.respond_to?(:length) ? coverage_lines.length : 0
      src_len = (exists && !read_error) ? safe_count_lines(file_abs) : 0

      # safe_count_lines returns the symbol :read_error on I/O failure rather than raising,
      # so that compute_file_staleness_details can cleanly distinguish a read error from a
      # zero-line file. Promote it to a boolean here and zero out src_len.
      read_error ||= src_len == :read_error
      src_len = 0 if read_error

      # Check if the source file has been modified since coverage was generated
      # Don't check for mismatch if we couldn't read the file
      len_mismatch = read_error ? false : length_mismatch?(cov_len, src_len)
      newer = check_file_newer_than_coverage(file_mtime, coverage_ts, len_mismatch, read_error)

      {
        exists:             exists,
        file_mtime:         file_mtime,
        coverage_timestamp: coverage_ts,
        cov_len:            cov_len,
        src_len:            src_len,
        newer:              newer,
        len_mismatch:       len_mismatch,
        read_error:         read_error,
      }
    end

    # Checks if the source line count differs from the coverage line count.
    #
    # Why this check exists:
    # - When a file is modified after coverage is generated, the line count often changes
    # - A mismatch indicates the coverage data is stale and no longer represents the current file
    # - We only flag as mismatch when coverage data exists (cov_len > 0)
    #
    # Note: Empty coverage (cov_len == 0) is not considered a mismatch, as it may represent
    # files that were never executed or files that are legitimately empty.
    private def length_mismatch?(cov_len, src_len)
      cov_len.positive? && src_len != cov_len
    end

    # Determines if a file has been modified more recently than the coverage timestamp.
    #
    # Why this check exists:
    # - Files modified after coverage generation may have behavioral changes not captured
    # - However, if there's already a length mismatch or read error, we prioritize that as the staleness indicator
    # - This prevents double-flagging: if lines changed, the file is already stale (length mismatch)
    #
    # The logic: newer &&= !len_mismatch && !read_error means:
    # - If len_mismatch or read_error is true, set newer to false (those take precedence)
    # - This way, staleness is categorized as either 'newer' (time-based), 'length_mismatch' (length-based),
    #   or 'error' (read error), not multiple
    private def check_file_newer_than_coverage(file_mtime, coverage_ts, len_mismatch, read_error)
      return false if coverage_ts.to_i <= 0

      newer = !!(file_mtime && file_mtime.to_i > coverage_ts.to_i)
      # If there's a length mismatch or read error, don't also flag as "newer" - those are more specific
      newer &&= !len_mismatch && !read_error
      newer
    end
  end
end
