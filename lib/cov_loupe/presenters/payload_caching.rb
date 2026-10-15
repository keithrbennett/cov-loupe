# frozen_string_literal: true

module CovLoupe
  module Presenters
    # Shared memoization logic for coverage payloads.
    #
    # Two-stage caching:
    #   1. absolute_payload — raw data with absolute file paths (cached per presenter instance)
    #   2. relativized_payload — same data with paths converted relative to project root
    #
    # Consumers must implement #compute_absolute_payload to define what data to fetch.
    #
    # @api private
    module PayloadCaching
      # Returns the absolute-path payload.
      # Consumers must implement #compute_absolute_payload.
      def absolute_payload
        @absolute_payload ||= compute_absolute_payload
      end

      # Returns the payload with file paths relativized for presentation.
      def relativized_payload
        @relativized_payload ||= model.relativize(absolute_payload)
      end

      private def compute_absolute_payload
        raise NotImplementedError, "#{self.class} must implement #compute_absolute_payload"
      end
    end
  end
end
