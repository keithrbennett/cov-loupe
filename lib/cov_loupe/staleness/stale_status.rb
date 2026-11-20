# frozen_string_literal: true

module CovLoupe
  # Helpers for working with staleness status values.
  #
  # Status values used across the codebase:
  #   - 'ok'             → file is fresh, coverage matches source
  #   - 'deleted'        → source file has been deleted
  #   - 'newer'          → source file mtime exceeds coverage timestamp
  #   - 'length_mismatch'→ source line count differs from coverage array length
  #   - 'unreadable'     → source file could not be read
  #
  # The same names are used as project totals stale.by_type keys (DELETED, NEWER,
  # LENGTH_MISMATCH, UNREADABLE) and match the list payload's *_files arrays.
  # Files without usable coverage data are counted under their own names:
  #   - NOT_IN_COVERAGE      → file matching the file globs, not in coverage data (not_in_coverage_files)
  #   - SKIPPED              → file skipped due to processing error
  #
  # @api private
  module StaleStatus
    OK = 'ok'
    DELETED = 'deleted'
    NEWER = 'newer'
    LENGTH_MISMATCH = 'length_mismatch'
    UNREADABLE = 'unreadable'
    VALID_STATUSES = [OK, DELETED, NEWER, LENGTH_MISMATCH, UNREADABLE].freeze
    NOT_IN_COVERAGE = 'not_in_coverage'
    SKIPPED = 'skipped'

    module_function def stale?(value)
      normalize(value) != OK
    end

    module_function def normalize(value)
      raise ArgumentError, 'Stale status is missing' if value.nil?
      unless value.is_a?(String)
        raise ArgumentError, "Stale status must be a String, got #{value.class} (value: #{value.inspect})"
      end
      return value if VALID_STATUSES.include?(value)

      raise ArgumentError, "Unknown stale status: #{value.inspect}. " \
                           "Permitted values: #{VALID_STATUSES.join(', ')}"
    end
  end
end
