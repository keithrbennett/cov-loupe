# frozen_string_literal: true

require 'time'
require 'json'
require 'set' # rubocop:disable Lint/RedundantRequireStatement -- Ruby >= 3.4 requires explicit require for set; RuboCop targets 3.2

require_relative '../errors/errors'
require_relative '../errors/error_handler'
require_relative '../staleness/staleness_checker'
require_relative '../staleness/stale_status'
require_relative '../paths/path_relativizer'
require_relative '../deprecation'
require_relative '../loaders/resultset_loader'
require_relative '../coverage/coverage_table_formatter'
require_relative '../coverage/coverage_calculator'
require_relative '../resolvers/resolver_helpers'
require_relative '../paths/glob_utils'
require_relative '../model/model_data_cache'
require_relative '../paths/path_utils'

module CovLoupe
  # Core domain model for querying SimpleCov coverage data.
  #
  # Provides file-level queries (raw_for, summary_for, uncovered_for, detailed_for),
  # project-level queries (list, project_totals), and table formatting (format_table).
  #
  # Construction eagerly validates that the coverage file exists and loads initial data
  # via ModelDataCache. Subsequent data accesses check the cache on every call and
  # auto-reload if the coverage file has changed (based on mtime + MD5 digest).
  #
  # The model delegates to:
  # - CoverageCalculator for line counting and aggregation
  # - StalenessChecker for time-based and line-count staleness detection
  # - CoverageLineResolver for looking up files in the coverage map
  # - PathRelativizer for converting absolute paths to project-relative form
  #
  # Thread safety: CoverageModel instances are NOT thread-safe. The shared
  # ModelDataCache is thread-safe, but per-instance state like @skipped_rows
  # is mutable and unsynchronized.
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

    DEFAULT_SORT_ORDER = :descending

    attr_reader :relativizer, :skipped_rows, :volume_case_sensitive, :coverage_file_path

    # Deprecated reader for coverage_file_path. Removed in v7.0.0.
    def resultset_path
      Deprecation.warn('CoverageModel#resultset_path', '#coverage_file_path')
      @coverage_file_path
    end

    # Create a CoverageModel
    #
    # Params:
    # - root: project root directory (default '.')
    # - coverage_file: path to a coverage.json or .resultset.json file, or to a
    #   directory containing one
    # - resultset: deprecated alias for coverage_file, removed in v7.0.0
    # - raise_on_stale: boolean (default false). When true, raises
    #   stale errors if sources are newer than coverage or line counts mismatch.
    # - tracked_globs: array of glob patterns (default []). Used for filtering and tracking.
    # - logger: logger instance (defaults to CovLoupe.logger)
    def initialize(root: '.', coverage_file: nil, resultset: nil, raise_on_stale: false,
      tracked_globs: [], logger: nil)
      if resultset && !coverage_file
        Deprecation.warn('CoverageModel.new(resultset:)', 'coverage_file:')
        coverage_file = resultset
      end

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
      # This is not cached because different models may use the same coverage file
      # with different root directories on different volumes
      @volume_case_sensitive = PathUtils.volume_case_sensitive?(@root)
    end

    # Returns { 'file' => <absolute_path>, 'lines' => [hits|nil,...] }
    def raw_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      { 'file' => file_abs, 'lines' => coverage_lines }
    end

    def relativize(payload)
      relativizer.relativize(payload)
    end

    # Returns { 'file' => <absolute_path>, 'summary' => {'covered'=>, 'total'=>, 'percentage'=>} }
    def summary_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      { 'file' => file_abs, 'summary' => CoverageCalculator.summary(coverage_lines) }
    end

    # Returns { 'file' => <absolute_path>, 'uncovered' => [line,...], 'summary' => {...} }
    def uncovered_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      {
        'file'      => file_abs,
        'uncovered' => CoverageCalculator.uncovered(coverage_lines),
        'summary'   => CoverageCalculator.summary(coverage_lines),
      }
    end

    # Returns { 'file' => <absolute_path>, 'lines' => [{'line'=>,'hits'=>,'covered'=>},...], 'summary' => {...} }
    def detailed_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      {
        'file'    => file_abs,
        'lines'   => CoverageCalculator.detailed(coverage_lines),
        'summary' => CoverageCalculator.summary(coverage_lines),
      }
    end

    # Returns a list of coverage data for all tracked files.
    #
    # @param sort_order [Symbol] :descending (default) or :ascending for sorting by percentage
    # @param raise_on_stale [Boolean] When true, raises errors if sources are newer than coverage
    # @param tracked_globs [Array<String>] Glob patterns to filter tracked files
    # @return [Hash] Hash containing:
    #   - 'files': Array of file coverage data sorted by percentage
    #   - 'skipped_files': Files that could not be processed
    #   - 'missing_tracked_files': Tracked files not in coverage data
    #   - 'newer_files': Coverage data older than source files
    #   - 'deleted_files': Source files removed since coverage run
    #   - 'length_mismatch_files': Files with line count mismatches
    #   - 'unreadable_files': Files that could not be read
    #   - 'timestamp_status': Overall staleness status
    #
    # @note Complexity: O(n log n) where n is the number of tracked files due to sorting.
    #   File I/O for staleness checks adds O(m) where m is the number of tracked source files.
    # @note Thread-safety: Not thread-safe. This method relies on shared mutable state
    #   (@skipped_rows, internal coverage_map) and should not be called concurrently
    #   from multiple threads on the same CoverageModel instance.
    def list(sort_order: DEFAULT_SORT_ORDER,
      raise_on_stale: @default_raise_on_stale,
      tracked_globs: @default_tracked_globs)
      @skipped_rows = []
      # Build rows in lenient mode to collect all data even if some files have errors
      # This ensures staleness checking can examine all files, not just the ones before
      # the first error. We'll re-raise any errors after staleness checking if needed.
      rows, coverage_lines_by_path = build_list_rows(
        tracked_globs:  tracked_globs,
        raise_on_stale: false # Always use lenient mode for row building
      )
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
        row['stale'] = file_statuses.fetch(row['file'], 'ok')
      end

      {
        'files'                 => sort_rows(rows, sort_order: sort_order),
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
      list_result = list(sort_order: :ascending, raise_on_stale: raise_on_stale,
        tracked_globs: tracked_globs)

      rows = list_result['files']

      included_rows = rows.reject { |row| StaleStatus.stale?(row['stale']) }
      line_totals = line_totals_from_rows(included_rows).merge(
        'included_files' => included_rows.length,
        'excluded_files' => rows.length - included_rows.length
      )

      tracking = tracking_payload(tracked_globs)
      with_coverage = with_coverage_payload(rows)
      without_coverage = without_coverage_payload(list_result, tracking['enabled'])
      files = files_payload(with_coverage, without_coverage)

      {
        'lines'            => line_totals,
        'tracking'         => tracking,
        'files'            => files,
        'timestamp_status' => list_result['timestamp_status'],
      }
    end

    def staleness_for(path)
      file_abs = File.expand_path(path, @root)
      coverage_lines = Resolvers::ResolverHelpers.lookup_lines(coverage_map, file_abs, root: @root,
        volume_case_sensitive: volume_case_sensitive)
      build_staleness_checker(raise_on_stale: false, tracked_globs: nil)
        .file_staleness_status(file_abs, coverage_lines)
    rescue => e
      @logger.safe_log("Failed to check staleness for #{path}: #{e.message}")
      'error'
    end

    # Returns formatted table string for all files coverage data
    # Delegates to CoverageTableFormatter for presentation logic
    #
    # @param rows [Array<Hash>, nil] Pre-computed rows, or nil to compute from coverage data
    # @param sort_order [Symbol] Sort order (:ascending or :descending)
    # @param raise_on_stale [Boolean] Whether to raise on stale coverage data
    # @param tracked_globs [Array<String>, nil] Glob patterns for tracked files
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

    private def build_list_rows(tracked_globs:, raise_on_stale:)
      coverage_lines_by_path = {}
      rows = coverage_map.filter_map do |abs_path, entry|
        # Extract lines directly from the entry to avoid O(n^2) resolver scans
        coverage_lines = coverage_lines_for_listing(abs_path, entry, raise_on_stale)
        next unless coverage_lines

        coverage_lines_by_path[abs_path] = coverage_lines
        summary = CoverageCalculator.summary(coverage_lines)
        {
          'file'       => abs_path,
          'covered'    => summary['covered'],
          'total'      => summary['total'],
          'percentage' => summary['percentage'],

          # We set 'stale' => 'ok' as a placeholder, then in list we overwrite it
          # with the true status from the project report.
          'stale'      => 'ok',
        }
      end

      [filter_rows_by_globs(rows, tracked_globs), coverage_lines_by_path]
    end

    private def coverage_lines_for_listing(abs_path, entry, raise_on_stale)
      # Try to extract lines directly from the entry (O(1) operation)
      # Only fall back to resolver if the entry is malformed
      lines = extract_lines_from_entry(entry)
      return lines if lines

      # Fallback to resolver for malformed entries
      Resolvers::ResolverHelpers.lookup_lines(coverage_map, abs_path, root: @root,
        volume_case_sensitive: volume_case_sensitive)
    rescue FileError, CoverageDataError => e
      # When raise_on_stale is true, raise all errors immediately for strict validation
      # When false, skip files with errors and report them in skipped_files for lenient mode
      raise e if raise_on_stale

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

    private def prepare_rows(rows, sort_order:, raise_on_stale:, tracked_globs:)
      files = rows || list(sort_order: sort_order, raise_on_stale: raise_on_stale,
        tracked_globs: tracked_globs)['files']

      files = sort_rows(files.dup, sort_order: sort_order)
      filter_rows_by_globs(files, tracked_globs)
    end

    private def sort_rows(rows, sort_order: :descending)
      # Two-level comparator: primary sort by coverage percentage, secondary by file path.
      # Nil percentages (e.g., files with no coverable lines) are grouped at one end:
      #   - Descending mode: nil files sort first (before 100%)
      #   - Ascending mode: nil files sort last (after 100%)
      percent_comparator = sort_order == :descending \
        ? ->(left, right) { right <=> left }
        : ->(left, right) { left <=> right }

      nil_comparator = ->(left, right) do
        left_nil = left['percentage'].nil?
        right_nil = right['percentage'].nil?
        return 0 if left_nil == right_nil

        # Keep rows without a computed percentage grouped at one end of the table.
        # In descending mode nil-percentage files (for example, files with no coverable
        # lines) sort first; in ascending mode they sort last.
        if sort_order == :descending
          left_nil ? -1 : 1
        else
          left_nil ? 1 : -1
        end
      end

      comparator = ->(a, b) do
        nil_comparison = nil_comparator.call(a, b)
        return nil_comparison unless nil_comparison.zero?

        if !a['percentage'].nil? && !b['percentage'].nil?
          percent_comp_result = percent_comparator.(a['percentage'], b['percentage'])
          return percent_comp_result if percent_comp_result != 0
        end

        a['file'] <=> b['file'] # stable tiebreaker: alphabetical by path
      end

      rows.sort { |a, b| comparator.(a, b) }
    end

    # Filters coverage rows to only include files matching the given glob patterns.
    #
    # @param rows [Array<Hash>] coverage rows with 'file' keys containing absolute paths
    # @param tracked_globs [Array<String>, String, nil] glob patterns to match against
    # @return [Array<Hash>] rows whose files match at least one pattern (or all rows if no patterns)
    private def filter_rows_by_globs(rows, tracked_globs)
      patterns = GlobUtils.normalize_patterns(tracked_globs)
      return rows if patterns.empty?

      absolute_patterns = patterns.map { |p| GlobUtils.absolutize_pattern(p, @root) }
      GlobUtils.filter_by_pattern(rows, absolute_patterns)
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

      # When raise_on_stale is false, allow missing files to return coverage data
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

    private def line_totals_from_rows(rows)
      CoverageCalculator.aggregate(rows)
    end

    private def tracking_payload(tracked_globs)
      patterns = GlobUtils.normalize_patterns(tracked_globs)
      {
        'enabled' => patterns.any?,
        'globs'   => patterns,
      }
    end

    private def with_coverage_payload(rows)
      breakdown = stale_breakdown(rows)
      stale_by_type = breakdown[:stale_by_type]
      stale_total = stale_by_type.values.sum

      {
        'total' => rows.length,
        'ok'    => breakdown[:ok],
        'stale' => {
          'total'   => stale_total,
          'by_type' => stale_by_type,
        },
      }
    end

    private def without_coverage_payload(list_result, tracking_enabled)
      return nil unless tracking_enabled

      missing_from_coverage = Array(list_result['missing_tracked_files']).length
      skipped = Array(list_result['skipped_files']).length
      unreadable = Array(list_result['unreadable_files']).length
      by_type = {
        StaleStatus::MISSING_FROM_COVERAGE => missing_from_coverage,
        StaleStatus::UNREADABLE            => unreadable,
        StaleStatus::SKIPPED               => skipped,
      }
      {
        'total'   => by_type.values.sum,
        'by_type' => by_type,
      }
    end

    private def files_payload(with_coverage, without_coverage)
      total = with_coverage['total']
      total += without_coverage['total'] if without_coverage

      files = {
        'total'         => total,
        'with_coverage' => with_coverage,
      }
      files['without_coverage'] = without_coverage if without_coverage
      files
    end

    private def stale_breakdown(rows)
      stale_by_type = {
        StaleStatus::MISSING_FROM_DISK => 0,
        StaleStatus::NEWER             => 0,
        StaleStatus::LENGTH_MISMATCH   => 0,
        StaleStatus::UNREADABLE        => 0,
      }
      ok_files = 0

      rows.each do |row|
        case row['stale']
        when 'ok'
          ok_files += 1
        when 'missing'
          stale_by_type[StaleStatus::MISSING_FROM_DISK] += 1
        when 'newer'
          stale_by_type[StaleStatus::NEWER] += 1
        when 'length_mismatch'
          stale_by_type[StaleStatus::LENGTH_MISMATCH] += 1
        when 'error'
          stale_by_type[StaleStatus::UNREADABLE] += 1
        end
      end

      {
        ok:            ok_files,
        stale_by_type: stale_by_type,
      }
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
