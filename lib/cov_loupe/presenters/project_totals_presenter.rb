# frozen_string_literal: true

require_relative 'payload_caching'

require_relative '../staleness/stale_status'
require_relative '../staleness/root_mismatch'

module CovLoupe
  module Presenters
    # Provides aggregated line totals and overall coverage (covered lines / coverable lines) across the project.
    #
    # @api private
    class ProjectTotalsPresenter
      include PayloadCaching

      attr_reader :model, :raise_on_stale, :tracked_globs

      def initialize(model:, raise_on_stale:, tracked_globs:)
        @model = model
        @raise_on_stale = raise_on_stale
        @tracked_globs = tracked_globs
      end

      # Returns the timestamp status indicating whether coverage timestamps are available.
      # Can be 'ok' (timestamps available) or 'missing' (no timestamps, staleness checks skipped).
      def timestamp_status
        payload['timestamp_status']
      end

      # Returns a warning when most files were not found under the project root, otherwise nil.
      def root_warning
        with_coverage = payload['file_counts']['with_coverage']
        RootMismatch.message(
          deleted_count: with_coverage['stale']['by_type'][StaleStatus::DELETED],
          total_count:   with_coverage['total'],
          root:          model.root
        )
      end

      private def compute_payload
        model.project_totals(
          tracked_globs:  tracked_globs,
          raise_on_stale: raise_on_stale
        )
      end
    end
  end
end
