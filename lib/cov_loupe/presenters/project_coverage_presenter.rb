# frozen_string_literal: true

require_relative 'payload_caching'

require_relative '../staleness/stale_status'
require_relative '../staleness/root_mismatch'

module CovLoupe
  module Presenters
    # Presenter for project-wide coverage summaries (list/coverage table).
    #
    # Wraps CoverageModel#list, whose payload it returns unchanged, with accessors for the
    # CLI and MCP renderers.
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

      # Returns the project-relative file rows.
      def relative_files
        payload['files']
      end

      # Returns the project-relative skipped files.
      def relative_skipped_files
        payload['skipped_files']
      end

      # Returns the project-relative missing tracked files.
      def relative_missing_tracked_files
        payload['missing_tracked_files']
      end

      # Returns the project-relative newer files.
      def relative_newer_files
        payload['newer_files']
      end

      # Returns the project-relative deleted files.
      def relative_deleted_files
        payload['deleted_files']
      end

      # Returns the project-relative length-mismatch files.
      def relative_length_mismatch_files
        payload['length_mismatch_files']
      end

      # Returns the project-relative unreadable files.
      def relative_unreadable_files
        payload['unreadable_files']
      end

      # Returns the timestamp status indicating whether coverage timestamps are available.
      # Can be 'ok' (timestamps available) or 'missing' (no timestamps, staleness checks skipped).
      def timestamp_status
        payload['timestamp_status']
      end

      # Returns a warning when most files were not found under the project root, otherwise nil.
      # Counts only rows with coverage, as ProjectTotalsPresenter#root_warning does.
      def root_warning
        RootMismatch.message(
          deleted_count: relative_files.count { |row| row['stale'] == StaleStatus::DELETED },
          total_count:   relative_files.length,
          root:          model.root
        ) { model.recorded_root }
      end

      private def compute_payload
        model.list(
          sort_order:     sort_order,
          raise_on_stale: raise_on_stale,
          tracked_globs:  tracked_globs
        )
      end
    end
  end
end
