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
  # When tracked_globs are provided, files without coverage data (missing from coverage,
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
    # @param tracked_globs [Array<String>, String, nil] glob patterns for tracked files
    # @return [Hash] 'lines', 'tracking', 'files', and 'timestamp_status' entries
    def build(list_result, tracked_globs:)
      patterns = GlobUtils.normalize_patterns(tracked_globs)
      without = without_coverage(list_result) if patterns.any?

      {
        'lines'            => line_totals(list_result['files']),
        'tracking'         => { 'enabled' => patterns.any?, 'globs' => patterns },
        'files'            => files(with_coverage(list_result['files']), without),
        'timestamp_status' => list_result['timestamp_status'],
      }
    end

    private def line_totals(rows)
      included_rows = rows.reject { |row| StaleStatus.stale?(row['stale']) }
      CoverageCalculator.aggregate(included_rows).merge(
        'included_files' => included_rows.length,
        'excluded_files' => rows.length - included_rows.length
      )
    end

    private def files(with, without)
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
        StaleStatus::MISSING_FROM_COVERAGE => Array(list_result['missing_tracked_files']).length,
        StaleStatus::UNREADABLE            => unreadable_without_row(list_result),
        StaleStatus::SKIPPED               => Array(list_result['skipped_files']).length,
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
