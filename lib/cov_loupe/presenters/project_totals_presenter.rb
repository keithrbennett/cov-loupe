# frozen_string_literal: true

require_relative 'project_presenter'

require_relative '../staleness/stale_status'
require_relative '../staleness/root_mismatch'

module CovLoupe
  module Presenters
    # Provides aggregated line totals and overall coverage (covered lines / coverable lines) across the project.
    #
    # @api private
    class ProjectTotalsPresenter < ProjectPresenter
      # Returns a warning when most files were not found under the project root, otherwise nil.
      def root_warning
        with_coverage = payload['file_counts']['with_coverage']
        RootMismatch.message(
          deleted_count: with_coverage['stale']['by_type'][StaleStatus::DELETED],
          total_count:   with_coverage['total'],
          root:          model.root
        ) { model.recorded_root }
      end

      private def compute_payload
        model.project_totals(
          file_globs:     file_globs,
          raise_on_stale: raise_on_stale
        )
      end
    end
  end
end
