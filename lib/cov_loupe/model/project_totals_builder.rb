# frozen_string_literal: true

require_relative '../coverage/coverage_calculator'
require_relative '../paths/glob_utils'
require_relative '../paths/path_utils'
require_relative '../staleness/stale_status'

module CovLoupe
  # Builds the project totals payload (without schema_version) from an unversioned
  # CoverageModel list result whose rows carry absolute paths.
  #
  # Stale files are excluded from line counts but still counted in the file breakdown.
  # When file_globs are provided, files without coverage data (not in coverage data,
  # skipped, or unreadable) are also reported.
  #
  # @api private
  class ProjectTotalsBuilder
    # Per-file stale values, which double as the stale.by_type keys.
    STALE_TYPES = (StaleStatus::VALID_STATUSES - [StaleStatus::OK]).freeze
    private_constant :STALE_TYPES

    def initialize(root:)
      @root = root
    end

    # @param list_result [Hash] unversioned list result with absolute paths
    # @param file_globs [Array<String>, String, nil] glob patterns; matching files are counted
    # @return [Hash] line metrics ('covered', 'uncovered', 'total', 'percentage') for fresh
    #   files, then 'file_globs', 'file_counts', and 'timestamp_status' entries
    def build(list_result, file_globs:)
      patterns = GlobUtils.normalize_patterns(file_globs)
      without = without_coverage(list_result) if patterns.any?
      fresh_rows = list_result['files'].reject { |row| StaleStatus.stale?(row['stale']) }

      CoverageCalculator.aggregate(fresh_rows).merge(
        'file_globs'       => patterns,
        'file_counts'      => file_counts(with_coverage(list_result['files']), without),
        'timestamp_status' => list_result['timestamp_status']
      )
    end

    private def file_counts(with, without)
      {
        'total'            => with['total'] + (without&.fetch('total') || 0),
        'with_coverage'    => with,
        'without_coverage' => without,
      }.compact
    end

    private def with_coverage(rows)
      counts = rows.map { |row| row['stale'] }.tally
      stale_by_type = STALE_TYPES.to_h { |type| [type, counts.fetch(type, 0)] }

      {
        'total' => rows.length,
        'ok'    => counts.fetch(StaleStatus::OK, 0),
        'stale' => { 'total' => stale_by_type.values.sum, 'by_type' => stale_by_type },
      }
    end

    private def without_coverage(list_result)
      by_type = {
        StaleStatus::NOT_IN_COVERAGE => Array(list_result['not_in_coverage_files']).length,
        StaleStatus::UNREADABLE      => unreadable_without_row(list_result),
        StaleStatus::SKIPPED         => Array(list_result['skipped_files']).length,
      }
      { 'total' => by_type.values.sum, 'by_type' => by_type }
    end

    # Unreadable files that already appear as a coverage row (counted under with_coverage)
    # or as a skipped file must not be counted again in the without-coverage bucket.
    private def unreadable_without_row(list_result)
      accounted = (list_result['files'] + Array(list_result['skipped_files'])).to_set { |r| r['file'] }
      Array(list_result['unreadable_files']).count do |path|
        !accounted.include?(PathUtils.expand_from_root(path, @root))
      end
    end
  end
end
