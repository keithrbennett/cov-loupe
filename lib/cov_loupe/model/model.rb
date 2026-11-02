# frozen_string_literal: true

require 'time'
require 'json'

require_relative '../errors/errors'
require_relative '../errors/error_handler'
require_relative '../staleness/staleness_checker'
require_relative '../staleness/stale_status'
require_relative '../paths/path_relativizer'
require_relative '../coverage/coverage_table_formatter'
require_relative '../coverage/coverage_calculator'
require_relative '../resolvers/resolver_helpers'
require_relative '../paths/glob_utils'
require_relative '../model/model_data_cache'
require_relative '../model/project_totals_builder'
require_relative '../model/coverage_row_sorter'
require_relative '../paths/path_utils'
require_relative '../payload_schema'

module CovLoupe
  # Core domain model for querying SimpleCov coverage data.
  #
  # Provides file-level queries (raw_for, summary_for, uncovered_for, detailed_for),
  # project-level queries (list, project_totals), and table formatting (format_table).
  #
  # Coverage data is keyed by absolute path internally. Query results report paths
  # relative to the project root; paths outside the root stay absolute.
  #
  # Construction eagerly validates that the coverage file exists and loads initial data
  # via ModelDataCache. Subsequent data accesses check the cache on every call and
  # auto-reload if the coverage file has changed (based on mtime + MD5 digest).
  #
  # The model delegates to:
  # - CoverageCalculator for line counting and aggregation
  # - StalenessChecker for time-based and line-count staleness detection
  # - CoverageLineResolver for looking up files in the coverage map
  # - PathRelativizer for converting result paths to project-relative form
  # - ProjectTotalsBuilder for aggregating list results into project totals
  # - CoverageRowSorter for ordering rows by percentage and path
  #
  # Thread safety: CoverageModel instances are NOT thread-safe. The shared
  # ModelDataCache is thread-safe, but per-instance state like @skipped_rows
  # is mutable and unsynchronized.
  #
  # @api public
  class CoverageModel
    RELATIVIZER_SCALAR_KEYS = %w[file file_path].freeze
    RELATIVIZER_ARRAY_KEYS = %w[
      newer_files
      deleted_files
      missing_tracked_files
      skipped_files
      length_mismatch_files
      unreadable_files
    ].freeze
    private_constant :RELATIVIZER_SCALAR_KEYS, :RELATIVIZER_ARRAY_KEYS

    # @api private
    DEFAULT_SORT_ORDER = :descending

    attr_reader :coverage_file_path

    # The absolute project root, resolved when the model was created. Expand a relative
    # result path against it to get an absolute path.
    # @return [String]
    attr_reader :root

    # @api private
    attr_reader :relativizer, :skipped_rows, :volume_case_sensitive

    # Create a CoverageModel
    #
    # Params:
    # - root: project root directory (default '.')
    # - coverage_file: path to a SimpleCov coverage.json file, or to a directory
    #   containing one
    # - raise_on_stale: boolean (default false). When true, raises if a source file is newer
    #   than the coverage, deleted, unreadable, or has a different line count; if a tracked
    #   file is missing from the coverage (project queries); or if a coverage row is skipped.
    # - tracked_globs: array of glob patterns, or one pattern string (default []). Used for
    #   filtering and tracking.
    # - logger: internal (@api private); a CovLoupe::Logger, defaulting to CovLoupe.logger.
    #   Library callers configure logging through the context instead.
    def initialize(root: '.', coverage_file: nil, raise_on_stale: false, tracked_globs: [],
      logger: nil)
      @root = File.expand_path(root || '.')
      @coverage_file_arg = coverage_file
      @default_tracked_globs = tracked_globs
      @skipped_rows = []
      @logger = logger || CovLoupe.logger
      @relativizer = PathRelativizer.new(
        root:        @root,
        scalar_keys: RELATIVIZER_SCALAR_KEYS,
        array_keys:  RELATIVIZER_ARRAY_KEYS
      )
      @default_raise_on_stale = raise_on_stale
      @resolved_coverage_file_path = nil # Resolved on first fetch

      # Eagerly validate the coverage file exists and load initial data
      # This matches original behavior and surfaces errors immediately
      begin
        data = fetch_data
        @coverage_file_path = data.coverage_file_path
      rescue CovLoupe::Error
        raise # Re-raise our own errors as-is
      rescue => e
        raise ErrorHandler.new.convert_standard_error(e, context: :coverage_loading)
      end

      # Compute volume case sensitivity based on this model's root directory
      # Computed per model, since models sharing a coverage file may have roots on different
      # volumes; PathUtils caches the result per root path
      @volume_case_sensitive = PathUtils.volume_case_sensitive?(@root)
    end

    # Returns { 'schema_version' => 1, 'file' => <relative_path>, 'lines' => [hits|nil,...] }
    def raw_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      # relative_paths returns a deep copy, so callers can't mutate the cached lines array
      relative_paths(PayloadSchema.add('file' => file_abs, 'lines' => coverage_lines))
    end

    # Returns { 'schema_version' => 1, 'file' => <relative_path>,
    #           'summary' => {'covered'=>, 'total'=>, 'percentage'=>} }
    def summary_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      relative_paths(PayloadSchema.add('file' => file_abs,
        'summary' => CoverageCalculator.summary(coverage_lines)))
    end

    # Returns { 'schema_version' => 1, 'file' => <relative_path>, 'uncovered' => [line,...],
    #           'summary' => {...} }
    def uncovered_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      relative_paths(PayloadSchema.add({
        'file'      => file_abs,
        'uncovered' => CoverageCalculator.uncovered(coverage_lines),
        'summary'   => CoverageCalculator.summary(coverage_lines),
      }))
    end

    # Returns { 'schema_version' => 1, 'file' => <relative_path>,
    #           'lines' => [{'line'=>,'hits'=>,'covered'=>},...], 'summary' => {...} }
    def detailed_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      relative_paths(PayloadSchema.add({
        'file'    => file_abs,
        'lines'   => CoverageCalculator.detailed(coverage_lines),
        'summary' => CoverageCalculator.summary(coverage_lines),
      }))
    end

    # Returns a list of coverage data for all tracked files.
    #
    # @param sort_order [Symbol] :descending (default) or :ascending for sorting by percentage
    # @param raise_on_stale [Boolean] When true, raises if any file is stale, a tracked file is
    #   missing from coverage, or a coverage row is skipped
    # @param tracked_globs [Array<String>, String] Glob patterns to filter tracked files
    # @return [Hash] Hash containing:
    #   - 'schema_version': Payload schema version (Integer)
    #   - 'files': Array of file coverage data sorted by percentage
    #   - 'skipped_files': Files that could not be processed
    #   - 'missing_tracked_files': Tracked files not in coverage data
    #   - 'newer_files': Coverage data older than source files
    #   - 'deleted_files': Source files removed since coverage run
    #   - 'length_mismatch_files': Files with line count mismatches
    #   - 'unreadable_files': Files that could not be read
    #   - 'timestamp_status': 'ok', or 'missing' when coverage has no timestamp
    #
    # @note Complexity: O(n log n) where n is the number of tracked files due to sorting.
    #   File I/O for staleness checks adds O(m) where m is the number of tracked source files.
    # @note Thread-safety: Not thread-safe. This method relies on shared mutable state
    #   (@skipped_rows, internal coverage_map) and should not be called concurrently
    #   from multiple threads on the same CoverageModel instance.
    def list(sort_order: DEFAULT_SORT_ORDER,
      raise_on_stale: @default_raise_on_stale,
      tracked_globs: @default_tracked_globs)
      relative_paths(PayloadSchema.add(unversioned_list(sort_order: sort_order,
        raise_on_stale: raise_on_stale, tracked_globs: tracked_globs)))
    end

    private def unversioned_list(sort_order:, raise_on_stale:, tracked_globs:)
      @skipped_rows = []
      # Build rows in lenient mode to collect all data even if some files have errors
      # This ensures staleness checking can examine all files, not just the ones before
      # the first error. We'll re-raise any errors after staleness checking if needed.
      rows, coverage_lines_by_path = build_list_rows(tracked_globs: tracked_globs)
      project_staleness_details = project_staleness_report(
        tracked_globs:          tracked_globs,
        raise_on_stale:         raise_on_stale, # Honor raise_on_stale for staleness checks
        coverage_lines_by_path: coverage_lines_by_path
      )

      # If raise_on_stale is true and there were any skipped files with errors,
      # raise the first error encountered after staleness checking is complete
      if raise_on_stale && @skipped_rows.any?
        first_error = @skipped_rows.first
        error_class = Object.const_get(first_error['error_class'])
        raise error_class, first_error['error']
      end

      file_statuses = project_staleness_details[:file_statuses] || {}
      length_mismatch_files = Array(project_staleness_details[:length_mismatch_files]).uniq
      unreadable_files = Array(project_staleness_details[:unreadable_files]).uniq
      rows.each do |row|
        row['stale'] = file_statuses.fetch(row['file'], StaleStatus::OK)
      end

      {
        'files'                 => CoverageRowSorter.sort(rows, sort_order: sort_order, root: @root),
        'skipped_files'         => filter_rows_by_globs(@skipped_rows, tracked_globs),
        'missing_tracked_files' => project_staleness_details[:missing_files],
        'newer_files'           => project_staleness_details[:newer_files],
        'deleted_files'         => project_staleness_details[:deleted_files],
        'length_mismatch_files' => length_mismatch_files,
        'unreadable_files'      => unreadable_files,
        'timestamp_status'      => project_staleness_details[:timestamp_status],
      }
    end

    # Aggregates per-file coverage into project-wide totals.
    # Partitions files by staleness: stale files are excluded from line counts
    # but still counted in the file breakdown. When tracked_globs are provided,
    # also reports files without coverage data (missing from coverage, skipped, unreadable).
    def project_totals(
      tracked_globs: @default_tracked_globs, raise_on_stale: @default_raise_on_stale
    )
      list_result = unversioned_list(sort_order: :ascending, raise_on_stale: raise_on_stale,
        tracked_globs: tracked_globs)
      PayloadSchema.add(
        ProjectTotalsBuilder.new(root: @root).build(list_result, tracked_globs: tracked_globs)
      )
    end

    def staleness_for(path)
      file_abs = File.expand_path(path, @root)
      coverage_lines = Resolvers::ResolverHelpers.lookup_lines(coverage_map, file_abs, root: @root,
        volume_case_sensitive: volume_case_sensitive)
      build_staleness_checker(raise_on_stale: false, tracked_globs: nil)
        .file_staleness_status(file_abs, coverage_lines)
    rescue => e
      @logger.safe_log("Failed to check staleness for #{path}: #{e.message}")
      StaleStatus::UNREADABLE
    end

    # Returns formatted table string for all files coverage data
    # Delegates to CoverageTableFormatter for presentation logic
    #
    # @param rows [Array<Hash>, nil] Pre-computed rows (e.g. list['files']), or nil to compute
    #   from coverage data
    # @param sort_order [Symbol] Sort order (:ascending or :descending)
    # @param raise_on_stale [Boolean] Whether to raise on stale coverage data; used only when
    #   rows is nil, since supplied rows are not rechecked
    # @param tracked_globs [Array<String>, String, nil] Glob patterns for tracked files
    # @param output_chars [Symbol] Output character mode (:default, :fancy, :ascii)
    # @return [String] Formatted table
    def format_table(rows = nil, sort_order: DEFAULT_SORT_ORDER,
      raise_on_stale: @default_raise_on_stale,
      tracked_globs: @default_tracked_globs,
      output_chars: :default)
      rows = prepare_rows(rows, sort_order: sort_order, raise_on_stale: raise_on_stale,
        tracked_globs: tracked_globs)
      CoverageTableFormatter.format(rows, output_chars: output_chars)
    end

    # Converts the configured path keys in a query result to project-relative form.
    private def relative_paths(payload)
      relativizer.relativize(payload)
    end

    # Lazily resolves the coverage file path on first access
    private def resolved_coverage_file_path
      @resolved_coverage_file_path ||= Resolvers::ResolverHelpers.find_coverage_file(
        @root, coverage_file: @coverage_file_arg
      )
    end

    # Fetches current ModelData from the shared cache
    # The cache automatically reloads if the coverage file has changed
    private def fetch_data
      ModelDataCache.instance.get(resolved_coverage_file_path, root: @root, logger: @logger)
    end

    # Returns the coverage map by delegating to ModelDataCache.
    # The cache automatically reloads if the coverage file has changed.
    private def coverage_map
      fetch_data.coverage_map
    end

    # Returns the timestamp by delegating to ModelDataCache.
    # The cache automatically reloads if the coverage file has changed.
    private def coverage_timestamp
      fetch_data.timestamp
    end

    # Clears the resolved coverage file path to allow re-resolution.
    # ModelDataCache automatically handles coverage file changes on each access,
    # so explicit refresh is rarely needed. This method is primarily for testing.
    #
    # @api private
    def refresh_data
      @resolved_coverage_file_path = nil
      self
    end

    private def build_staleness_checker(raise_on_stale:, tracked_globs:)
      StalenessChecker.new(
        root:          @root,
        coverage_file: resolved_coverage_file_path,
        mode:          raise_on_stale ? :error : :off,
        tracked_globs: tracked_globs,
        timestamp:     coverage_timestamp
      )
    end

    private def build_list_rows(tracked_globs:)
      coverage_lines_by_path = {}
      rows = coverage_map.filter_map do |abs_path, entry|
        # Extract lines directly from the entry to avoid O(n^2) resolver scans
        coverage_lines = coverage_lines_for_listing(abs_path, entry)
        next unless coverage_lines

        coverage_lines_by_path[abs_path] = coverage_lines
        summary = CoverageCalculator.summary(coverage_lines)
        {
          'file'       => abs_path,
          'covered'    => summary['covered'],
          'total'      => summary['total'],
          'percentage' => summary['percentage'],

          # We set 'stale' => StaleStatus::OK as a placeholder, then in list we overwrite it
          # with the true status from the project report.
          'stale'      => StaleStatus::OK,
        }
      end

      [filter_rows_by_globs(rows, tracked_globs), coverage_lines_by_path]
    end

    private def coverage_lines_for_listing(abs_path, entry)
      # Try to extract lines directly from the entry (O(1) operation)
      # Only fall back to resolver if the entry is malformed
      lines = extract_lines_from_entry(entry)
      return lines if lines

      # Fallback to resolver for malformed entries
      Resolvers::ResolverHelpers.lookup_lines(coverage_map, abs_path, root: @root,
        volume_case_sensitive: volume_case_sensitive)
    rescue FileError, CoverageDataError => e
      # Skip files with errors and report them in skipped_files; `list` re-raises the
      # first one afterwards when raise_on_stale is set.
      @logger.safe_log("Skipping coverage row for #{abs_path}: #{e.message}")
      @skipped_rows << {
        'file'        => abs_path,
        'error'       => e.message,
        'error_class' => e.class.name,
      }
      nil
    end

    private def project_staleness_report(tracked_globs:, raise_on_stale:, coverage_lines_by_path:)
      # Filter coverage files to match the same scope as tracked_globs
      coverage_files = GlobUtils.filter_paths(coverage_map.keys, tracked_globs, root: @root)

      # Filter coverage_lines_by_path to the same scope to ensure length-mismatch
      # checks only apply to files within the tracked_globs scope
      coverage_files_set = coverage_files.to_set
      scoped_coverage_lines = coverage_lines_by_path.slice(*coverage_files_set)

      build_staleness_checker(
        raise_on_stale: raise_on_stale, tracked_globs: tracked_globs
      ).check_project_with_lines!(scoped_coverage_lines, coverage_files: coverage_files)
    end

    # Rows computed here come from list, already sorted and glob-filtered; supplied rows
    # still need both.
    private def prepare_rows(rows, sort_order:, raise_on_stale:, tracked_globs:)
      unless rows
        return list(sort_order: sort_order, raise_on_stale: raise_on_stale,
          tracked_globs: tracked_globs)['files']
      end

      sorted = CoverageRowSorter.sort(rows, sort_order: sort_order, root: @root)
      filter_rows_by_globs(sorted, tracked_globs)
    end

    # Filters coverage rows to only include files matching the given glob patterns.
    #
    # @param rows [Array<Hash>] coverage rows with 'file' keys containing absolute paths, or
    #   project-relative paths when format_table receives rows from a query result
    # @param tracked_globs [Array<String>, String, nil] glob patterns to match against
    # @return [Array<Hash>] rows whose files match at least one pattern (or all rows if no patterns)
    private def filter_rows_by_globs(rows, tracked_globs)
      patterns = GlobUtils.normalize_patterns(tracked_globs)
      return rows if patterns.empty?

      absolute_patterns = patterns.map { |p| GlobUtils.absolutize_pattern(p, @root) }
      GlobUtils.filter_by_pattern(rows, absolute_patterns, root: @root)
    end

    # Retrieves coverage data for a file path.
    # Converts the path to absolute form and performs staleness checking if enabled.
    #
    # @param path [String] relative or absolute file path
    # @return [Array(String, Array)] tuple of [absolute_path, coverage_lines]
    # @raise [FileError] if no coverage data exists for the file
    # @raise [FileNotFoundError] if the file does not exist and raise_on_stale is true
    # @raise [CoverageDataStaleError] if staleness checking is enabled and data is stale
    private def coverage_data_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs = File.expand_path(path, @root)
      coverage_lines = Resolvers::ResolverHelpers.lookup_lines(coverage_map, file_abs, root: @root,
        volume_case_sensitive: volume_case_sensitive)

      if coverage_lines.nil?
        raise FileError, "No coverage data found for file: #{path}"
      end

      # When raise_on_stale is false, allow deleted files to return coverage data
      # The staleness status will be added by the presenter via staleness_for
      if raise_on_stale && !File.file?(file_abs)
        raise FileNotFoundError, "File not found: #{path}"
      end

      checker = build_staleness_checker(raise_on_stale: raise_on_stale, tracked_globs: nil)
      checker.check_file!(file_abs, coverage_lines) unless checker.off?

      [file_abs, coverage_lines]
    rescue Errno::ENOENT
      raise FileNotFoundError, "File not found: #{path}" if raise_on_stale

      [file_abs, coverage_lines]
    end

    # Extract coverage lines from a SimpleCov entry.
    # Returns nil if the entry is not a valid Hash, does not contain a lines array,
    # or contains invalid elements. Invalid entries trigger fallback to the resolver,
    # which performs centralized validation and error handling.
    #
    # @param entry [Hash, Object] coverage entry from the coverage file
    # @return [Array<Integer, nil>, nil] SimpleCov-style line coverage array or nil
    private def extract_lines_from_entry(entry)
      return unless entry.is_a?(Hash)

      lines = entry['lines']
      unless lines.is_a?(Array)
        @logger.safe_log("Invalid coverage lines encountered (not an array): #{lines.class}") if lines
        return nil
      end

      # Validate all elements - return nil to trigger resolver fallback on validation failure
      # The resolver will raise CoverageDataError with a detailed message
      return nil unless lines.all? { |v| v.nil? || v.is_a?(Integer) }

      lines
    end
  end
end
