# frozen_string_literal: true

require_relative 'payload_caching'

require_relative '../staleness/stale_status'

module CovLoupe
  module Presenters
    # Presenter for project-wide coverage summaries (list/coverage table).
    #
    # Wraps CoverageModel#list and enriches the output with:
    # - File counts (total, ok, stale) for quick overview
    # - Relativized paths for all file lists (skipped, missing, newer, deleted, etc.)
    #
    # @api private
    class ProjectCoveragePresenter
      include PayloadCaching

      attr_reader :model, :sort_order, :raise_on_stale, :tracked_globs

      def initialize(model:, sort_order:, raise_on_stale:, tracked_globs:)
        @model = model
        @sort_order = sort_order
        @raise_on_stale = raise_on_stale
        @tracked_globs = tracked_globs
      end

      # Returns the relativized file rows.
      def relative_files
        relativized_payload['files']
      end

      # Returns the coverage counts with relative file paths.
      def relative_counts
        relativized_payload['counts']
      end

      # Returns the relativized skipped files.
      def relative_skipped_files
        relativized_payload['skipped_files']
      end

      # Returns the relativized missing tracked files.
      def relative_missing_tracked_files
        relativized_payload['missing_tracked_files']
      end

      # Returns the relativized newer files.
      def relative_newer_files
        relativized_payload['newer_files']
      end

      # Returns the relativized deleted files.
      def relative_deleted_files
        relativized_payload['deleted_files']
      end

      # Returns the relativized length-mismatch files.
      def relative_length_mismatch_files
        relativized_payload['length_mismatch_files']
      end

      # Returns the relativized unreadable files.
      def relative_unreadable_files
        relativized_payload['unreadable_files']
      end

      # Returns the timestamp status indicating whether coverage timestamps are available.
      # Can be 'ok' (timestamps available) or 'missing' (no timestamps, staleness checks skipped).
      def timestamp_status
        relativized_payload['timestamp_status']
      end

      private def compute_absolute_payload
        list_result = model.list(
          sort_order:     sort_order,
          raise_on_stale: raise_on_stale,
          tracked_globs:  tracked_globs
        )
        files = list_result['files']
        skipped_files = list_result['skipped_files']
        missing_tracked_files = list_result['missing_tracked_files']
        newer_files = list_result['newer_files']
        deleted_files = list_result['deleted_files']
        length_mismatch_files = list_result['length_mismatch_files']
        unreadable_files = list_result['unreadable_files']
        timestamp_status = list_result['timestamp_status']
        {
          'files'                 => files,
          'skipped_files'         => skipped_files,
          'missing_tracked_files' => missing_tracked_files,
          'newer_files'           => newer_files,
          'deleted_files'         => deleted_files,
          'length_mismatch_files' => length_mismatch_files,
          'unreadable_files'      => unreadable_files,
          'timestamp_status'      => timestamp_status,
          'counts'                => build_counts(files),
        }
      end

      private def build_counts(files)
        total = files.length
        stale = files.count { |f| StaleStatus.stale?(f['stale']) }
        { 'total' => total, 'ok' => total - stale, 'stale' => stale }
      end
    end
  end
end
