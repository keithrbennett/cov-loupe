# frozen_string_literal: true

require_relative 'payload_caching'

module CovLoupe
  module Presenters
    # Shared presenter behavior for project-wide payloads (ProjectCoveragePresenter and
    # ProjectTotalsPresenter). Subclasses implement #compute_payload.
    #
    # @api private
    class ProjectPresenter
      include PayloadCaching

      attr_reader :model, :raise_on_stale, :file_globs

      def initialize(model:, raise_on_stale:, file_globs:)
        @model = model
        @raise_on_stale = raise_on_stale
        @file_globs = file_globs
      end

      # Returns the timestamp status indicating whether coverage timestamps are available.
      # Can be 'ok' (timestamps available) or 'missing' (no timestamps, staleness checks skipped).
      def timestamp_status
        payload['timestamp_status']
      end
    end
  end
end
