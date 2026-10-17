# frozen_string_literal: true

module CovLoupe
  module Presenters
    # Shared memoization logic for coverage payloads.
    #
    # The payload is computed once per presenter instance. Its paths are already
    # project-relative because CoverageModel query methods return them that way.
    #
    # Consumers must implement #compute_payload to define what data to fetch.
    #
    # @api private
    module PayloadCaching
      # Returns the cached payload.
      # Consumers must implement #compute_payload.
      def payload
        @payload ||= compute_payload
      end

      private def compute_payload
        raise NotImplementedError, "#{self.class} must implement #compute_payload"
      end
    end
  end
end
