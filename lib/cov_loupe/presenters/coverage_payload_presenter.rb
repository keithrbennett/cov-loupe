# frozen_string_literal: true

require_relative 'base_coverage_presenter'

module CovLoupe
  module Presenters
    # Presenter for single-file coverage queries (summary, raw, detailed, uncovered).
    #
    # Delegates to a CoverageModel method (specified by payload_method) and adds
    # staleness status. Used by both CLI commands and MCP tools.
    #
    # @api private
    class CoveragePayloadPresenter < BaseCoveragePresenter
      def initialize(model:, path:, payload_method:, raise_on_stale: nil)
        super(model: model, path: path)
        @payload_method = payload_method
        @raise_on_stale = raise_on_stale
      end

      private def build_payload
        args = { raise_on_stale: @raise_on_stale }.compact
        model.public_send(@payload_method, path, **args)
      end
    end
  end
end
