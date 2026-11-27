# frozen_string_literal: true

require_relative 'base_tool'
require_relative 'presenters/coverage_payload_presenter'

module CovLoupe
  # Base class for the file-scope MCP tools (summary, raw, detailed, uncovered). Each subclass
  # supplies only its name and description: it gets the file input schema, and its call
  # derives the CoverageModel method from the class name, so a subclass must be named
  # File[Coverage]<Name>[Lines]Tool for a CoverageModel#<name>_for method (see payload_method).
  #
  # @api private
  class FileTool < BaseTool
    INPUT_SCHEMA = coverage_schema(
      additional_properties: { path: PATH_PROPERTY },
      required:              ['path']
    )

    class << self
      # MCP::Tool.inherited resets each subclass's input schema, so it is set here rather
      # than once on this class.
      def inherited(subclass)
        super
        subclass.input_schema(**INPUT_SCHEMA)
      end

      def call(path:, root: nil, coverage_file: nil, raise_on_stale: nil,
        output_chars: nil, server_context:)
        with_model(server_context: server_context, output_chars: output_chars, root: root,
          coverage_file: coverage_file, raise_on_stale: raise_on_stale) do |model, config, chars|
          presenter = Presenters::CoveragePayloadPresenter.new(
            model:          model,
            path:           path,
            payload_method: payload_method,
            raise_on_stale: config[:raise_on_stale]
          )
          respond_json(presenter.payload, pretty: true, output_chars: chars)
        end
      end

      # Infer the CoverageModel method name from the tool class name.
      # FileCoverageSummaryTool -> :summary_for, FileCoverageRawTool -> :raw_for,
      # FileCoverageDetailedTool -> :detailed_for, FileUncoveredLinesTool -> :uncovered_for.
      private def payload_method
        underscored = underscore(name.split('::').last.sub(/Tool\z/, ''))
          .sub(/\A(file_)?(coverage_)?/, '')
          .sub(/_lines\z/, '')
        :"#{underscored}_for"
      end

      # Minimal underscore helper to avoid pulling in ActiveSupport.
      private def underscore(value)
        value
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
          .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
          .downcase
      end
    end
  end
end
