# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../model/model'
require_relative '../presenters/coverage_payload_presenter'

module CovLoupe
  module Tools
    # @api private
    class FileCoverageDetailedTool < BaseTool
      tool_name 'file_coverage_detailed'
      description <<~DESC
        Use this when the user needs per-line coverage data for a single file.
        Do not use this for high-level counts; file_coverage_summary is cheaper for aggregate numbers.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale/error_mode/output_chars.
        Output: JSON object with "schema_version" (Integer), "file", "lines" => [{"line": 12, "hits": 0, "covered": false}], plus "summary" with totals {"covered","total","percentage"} (percentage is null if the file has no coverable lines) and "stale": "ok" | "deleted" | "newer" | "length_mismatch" | "unreadable".
        Example: "Show detailed coverage for lib/my_app/order.rb".
      DESC
      input_schema(**input_schema_def)
      class << self
        def call(path:, root: nil, coverage_file: nil, raise_on_stale: nil,
          error_mode: nil, output_chars: nil, server_context:)
          call_with_file_payload(
            path:           path,
            error_mode:     error_mode,
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
