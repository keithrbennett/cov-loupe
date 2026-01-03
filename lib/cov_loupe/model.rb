# frozen_string_literal: true

require 'time'
require 'json'
require 'set' # rubocop:disable Lint/RedundantRequireStatement -- Ruby >= 3.4 requires explicit require for set; RuboCop targets 3.2

require_relative 'errors'
require_relative 'error_handler'
require_relative 'staleness_checker'
require_relative 'path_relativizer'
require_relative 'resultset_loader'
require_relative 'coverage_table_formatter'
require_relative 'coverage_calculator'
require_relative 'resolvers/resolver_helpers'
require_relative 'glob_utils'
require_relative 'repositories/coverage_repository'

module CovLoupe
  class CoverageModel
    RELATIVIZER_SCALAR_KEYS = %w[file file_path].freeze
    RELATIVIZER_ARRAY_KEYS = %w[
      newer_files
      missing_files
      deleted_files
      missing_tracked_files
      skipped_files
      length_mismatch_files
      unreadable_files
    ].freeze

    DEFAULT_SORT_ORDER = :descending

    attr_reader :relativizer, :skipped_rows

    # Create a CoverageModel
    #
    # Params:
    # - root: project root directory (default '.')
    # - resultset: path or directory to .resultset.json
    # - raise_on_stale: boolean (default false). When true, raises
    #   stale errors if sources are newer than coverage or line counts mismatch.
    # - tracked_globs: only used for list project-level staleness.
    # - logger: logger instance (defaults to CovLoupe.logger)
    def initialize(root: '.', resultset: nil, raise_on_stale: false, tracked_globs: nil,
      logger: nil)
      @root = File.expand_path(root || '.')
      @resultset_arg = resultset
      @default_tracked_globs = tracked_globs
      @skipped_rows = []
      @logger = logger || CovLoupe.logger
      @relativizer = PathRelativizer.new(
        root: @root,
        scalar_keys: RELATIVIZER_SCALAR_KEYS,
        array_keys: RELATIVIZER_ARRAY_KEYS
      )
      @default_raise_on_stale = raise_on_stale

      load_coverage_data
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
        'file' => file_abs,
        'uncovered' => CoverageCalculator.uncovered(coverage_lines),
        'summary' => CoverageCalculator.summary(coverage_lines)
      }
    end

    # Returns { 'file' => <absolute_path>, 'lines' => [{'line'=>,'hits'=>,'covered'=>},...], 'summary' => {...} }
    def detailed_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs, coverage_lines = coverage_data_for(path, raise_on_stale: raise_on_stale)
      {
        'file' => file_abs,
        'lines' => CoverageCalculator.detailed(coverage_lines),
        'summary' => CoverageCalculator.summary(coverage_lines)
      }
    end

    # Returns [ { 'file' =>, 'covered' =>, 'total' =>, 'percentage' =>, 'stale' => }, ... ]
    def list(sort_order: DEFAULT_SORT_ORDER,
      raise_on_stale: @default_raise_on_stale,
      tracked_globs: @default_tracked_globs)
      @skipped_rows = []
      rows, coverage_lines_by_path = build_list_rows(
        tracked_globs: tracked_globs,
        raise_on_stale: raise_on_stale
      )
      project_staleness_details = project_staleness_report(
        tracked_globs: tracked_globs,
        raise_on_stale: raise_on_stale,
        coverage_lines_by_path: coverage_lines_by_path
      )
      file_statuses = project_staleness_details[:file_statuses] || {}
      length_mismatch_files = Array(project_staleness_details[:length_mismatch_files]).uniq
      unreadable_files = Array(project_staleness_details[:unreadable_files]).uniq
      rows.each do |row|
        row['stale'] = file_statuses.fetch(row['file'], false)
      end

      {
        'files' => sort_rows(rows, sort_order: sort_order),
        'skipped_files' => filter_rows_by_globs(@skipped_rows, tracked_globs),
        'missing_tracked_files' => project_staleness_details[:missing_files],
        'newer_files' => project_staleness_details[:newer_files],
        'deleted_files' => project_staleness_details[:deleted_files],
        'length_mismatch_files' => length_mismatch_files,
        'unreadable_files' => unreadable_files,
        'timestamp_status' => project_staleness_details[:timestamp_status]
      }
    end

    def project_totals(
      tracked_globs: @default_tracked_globs, raise_on_stale: @default_raise_on_stale
    )
      list_result = list(sort_order: :ascending, raise_on_stale: raise_on_stale,
        tracked_globs: tracked_globs)

      rows = list_result['files']

      included_rows = rows.reject { |row| row['stale'] }
      line_totals = line_totals_from_rows(included_rows)

      tracking = tracking_payload(tracked_globs)
      with_coverage = with_coverage_payload(rows)
      without_coverage = without_coverage_payload(list_result, tracking['enabled'])
      files = files_payload(with_coverage, without_coverage)

      {
        'lines' => line_totals,
        'tracking' => tracking,
        'files' => files
      }
    end

    def staleness_for(path)
      file_abs = File.expand_path(path, @root)
      coverage_lines = Resolvers::ResolverHelpers.lookup_lines(@cov, file_abs, root: @root,
        volume_case_sensitive: volume_case_sensitive)
      build_staleness_checker(raise_on_stale: false, tracked_globs: nil)
        .stale_for_file?(file_abs, coverage_lines)
    rescue => e
      @logger.safe_log("Failed to check staleness for #{path}: #{e.message}")
      'E'
    end

    # Returns formatted table string for all files coverage data
    # Delegates to CoverageTableFormatter for presentation logic
    def format_table(rows = nil, sort_order: DEFAULT_SORT_ORDER,
      raise_on_stale: @default_raise_on_stale,
      tracked_globs: @default_tracked_globs)
      rows = prepare_rows(rows, sort_order: sort_order, raise_on_stale: raise_on_stale,
        tracked_globs: tracked_globs)
      CoverageTableFormatter.format(rows)
    end

    private def volume_case_sensitive
      return @volume_case_sensitive if defined?(@volume_case_sensitive)

      @volume_case_sensitive = Resolvers::ResolverHelpers.volume_case_sensitive?(@root)
    end

    private def load_coverage_data
      repo = Repositories::CoverageRepository.new(
        root: @root,
        resultset_path: @resultset_arg,
        logger: @logger
      )
      @cov = repo.coverage_map or raise(CoverageDataError, "No 'coverage' key found in resultset file: #{repo.resultset_path}")
      @cov_timestamp = repo.timestamp
      @resultset_path = repo.resultset_path # Store resolved path for StalenessChecker
    end

    private def build_staleness_checker(raise_on_stale:, tracked_globs:)
      StalenessChecker.new(
        root: @root,
        resultset: @resultset_path,
        mode: raise_on_stale ? :error : :off,
        tracked_globs: tracked_globs,
        timestamp: @cov_timestamp
      )
    end

    private def build_list_rows(tracked_globs:, raise_on_stale:)
      coverage_lines_by_path = {}
      rows = @cov.filter_map do |abs_path, entry|
        # Extract lines directly from the entry to avoid O(n^2) resolver scans
        coverage_lines = coverage_lines_for_listing(abs_path, entry, raise_on_stale)
        next unless coverage_lines

        coverage_lines_by_path[abs_path] = coverage_lines
        summary = CoverageCalculator.summary(coverage_lines)
        {
          'file' => abs_path,
          'covered' => summary['covered'],
          'total' => summary['total'],
          'percent_covered' => summary['percent_covered'],

          # We set 'stale' => false as a placeholder, then in list we overwrite it
          # with the true status from the project report.
          'stale' => false
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
      Resolvers::ResolverHelpers.lookup_lines(@cov, abs_path, root: @root,
        volume_case_sensitive: volume_case_sensitive)
    rescue FileError, CoverageDataError => e
      raise e if raise_on_stale

      @logger.safe_log("Skipping coverage row for #{abs_path}: #{e.message}")
      @skipped_rows << {
        'file' => abs_path,
        'error' => e.message,
        'error_class' => e.class.name
      }
      nil
    end

    private def project_staleness_report(tracked_globs:, raise_on_stale:, coverage_lines_by_path:)
      # Filter coverage files to match the same scope as tracked_globs
      coverage_files = GlobUtils.filter_paths(@cov.keys, tracked_globs, root: @root)

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
      percent_comparator = sort_order == :descending \
        ? ->(a, b) { b['percent_covered'] <=> a['percent_covered'] }
        : ->(a, b) { a['percent_covered'] <=> b['percent_covered'] }

      comparator = ->(a, b) do
        percent_comp_result = percent_comparator.(a, b)
        return percent_comp_result if percent_comp_result != 0

        a['file'] <=> b['file']
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
    # @raise [FileNotFoundError] if the file does not exist
    # @raise [CoverageDataStaleError] if staleness checking is enabled and data is stale
    private def coverage_data_for(path, raise_on_stale: @default_raise_on_stale)
      file_abs = File.expand_path(path, @root)
      coverage_lines = Resolvers::ResolverHelpers.lookup_lines(@cov, file_abs, root: @root,
        volume_case_sensitive: volume_case_sensitive)

      if coverage_lines.nil?
        raise FileError, "No coverage data found for file: #{path}"
      end

      # Check file existence before staleness check
      # Missing files are fundamentally different from stale files and should be
      # reported as such regardless of raise_on_stale setting
      unless File.file?(file_abs)
        raise FileNotFoundError, "File not found: #{path}"
      end

      checker = build_staleness_checker(raise_on_stale: raise_on_stale, tracked_globs: nil)
      checker.check_file!(file_abs, coverage_lines) unless checker.off?

      [file_abs, coverage_lines]
    rescue Errno::ENOENT
      raise FileNotFoundError, "File not found: #{path}"
    end

    private def line_totals_from_rows(rows)
      covered = rows.sum { |row| row['covered'].to_i }
      total = rows.sum { |row| row['total'].to_i }
      uncovered = total - covered
      percent_covered = total.zero? ? 100.0 : ((covered.to_f * 100.0 / total) * 100).round / 100.0

      {
        'covered' => covered,
        'uncovered' => uncovered,
        'total' => total,
        'percent_covered' => percent_covered
      }
    end

    private def tracking_payload(tracked_globs)
      patterns = GlobUtils.normalize_patterns(tracked_globs)
      {
        'enabled' => patterns.any?,
        'globs' => patterns
      }
    end

    private def with_coverage_payload(rows)
      breakdown = stale_breakdown(rows)
      stale_by_type = breakdown[:stale_by_type]
      stale_total = stale_by_type.values.sum

      {
        'total' => rows.length,
        'ok' => breakdown[:ok],
        'stale' => {
          'total' => stale_total,
          'by_type' => stale_by_type
        }
      }
    end

    private def without_coverage_payload(list_result, tracking_enabled)
      return nil unless tracking_enabled

      missing_from_coverage = Array(list_result['missing_tracked_files']).length
      skipped = Array(list_result['skipped_files']).length
      by_type = {
        'missing_from_coverage' => missing_from_coverage,
        'unreadable' => 0,
        'skipped' => skipped
      }
      {
        'total' => by_type.values.sum,
        'by_type' => by_type
      }
    end

    private def files_payload(with_coverage, without_coverage)
      total = with_coverage['total']
      total += without_coverage['total'] if without_coverage

      files = {
        'total' => total,
        'with_coverage' => with_coverage
      }
      files['without_coverage'] = without_coverage if without_coverage
      files
    end

    private def stale_breakdown(rows)
      stale_by_type = {
        'missing_from_disk' => 0,
        'newer' => 0,
        'length_mismatch' => 0,
        'unreadable' => 0
      }
      ok_files = 0

      rows.each do |row|
        case row['stale']
        when false, nil
          ok_files += 1
        when 'M'
          stale_by_type['missing_from_disk'] += 1
        when 'T'
          stale_by_type['newer'] += 1
        when 'L'
          stale_by_type['length_mismatch'] += 1
        else # including 'E'
          stale_by_type['unreadable'] += 1
        end
      end

      {
        ok: ok_files,
        stale_by_type: stale_by_type
      }
    end

    # Extract coverage lines from a SimpleCov entry.
    # Returns nil if the entry is not a valid Hash or does not contain a lines array.
    #
    # @param entry [Hash, Object] coverage entry from the resultset
    # @return [Array<Integer, nil>, nil] SimpleCov-style line coverage array or nil
    private def extract_lines_from_entry(entry)
      return unless entry.is_a?(Hash)

      lines = entry['lines']
      lines.is_a?(Array) ? lines : nil
    end
  end
end
