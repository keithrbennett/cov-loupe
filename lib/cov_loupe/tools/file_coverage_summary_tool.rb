# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../model/model'
require_relative '../presenters/coverage_payload_presenter'

module CovLoupe
  module Tools
    # @api private
    class FileCoverageSummaryTool < BaseTool
      tool_name 'file_coverage_summary'
      description <<~DESC
        Use this when the user asks for the covered/total line counts and percentage for a specific file.
        Do not use this for multi-file reports; use project_coverage for per-file listings or project_coverage_totals for aggregate totals.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale/output_chars.
        Output: JSON object {"schema_version": Integer, "file": String, "covered": Integer, "uncovered": Integer, "total": Integer, "percentage": Float | null, "stale": "ok" | "deleted" | "newer" | "length_mismatch" | "unreadable"}.
        Example: "What is the coverage for lib/my_app/order.rb?".
      DESC
      input_schema(**input_schema_def)
      class << self
        def call(path:, root: nil, coverage_file: nil, raise_on_stale: nil,
          output_chars: nil, server_context:)
          call_with_file_payload(
            path:           path,
            output_chars:   output_chars,
            server_context: server_context,
            root:           root,
            coverage_file:  coverage_file,
            raise_on_stale: raise_on_stale
          )
        end
      end
    end
  end
end
