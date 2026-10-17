# frozen_string_literal: true

require_relative 'payload_caching'

module CovLoupe
  module Presenters
    # Shared presenter behavior for single-file coverage payloads.
    #
    # Subclasses must implement #build_payload, which calls a CoverageModel
    # method (e.g., :summary_for, :raw_for) for the given file path.
    # The base class enriches the payload with staleness status from model.staleness_for.
    #
    # @api private
    class BaseCoveragePresenter
      include PayloadCaching

      attr_reader :model, :path

      def initialize(model:, path:)
        @model = model
        @path = path
      end

      # Returns the cached stale status for the file.
      def stale
        payload['stale']
      end

      # Returns the project-relative file path used in CLI output.
      def relative_path
        payload['file']
      end

      private def compute_payload
        build_payload.merge('stale' => model.staleness_for(path))
      end

      private def build_payload
        raise NotImplementedError, "#{self.class} must implement #build_payload"
      end
    end
  end
end
