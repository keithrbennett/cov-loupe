# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../model/model'
require_relative '../presenters/coverage_payload_presenter'

module CovLoupe
  module Tools
    class FileCoverageDetailedTool < BaseTool
      tool_name 'file_coverage_detailed'
      description <<~DESC
        Use this when the user needs per-line coverage data for a single file.
        Do not use this for high-level counts; coverage.summary is cheaper for aggregate numbers.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale flag inherited from BaseTool.
        Output: JSON object with "file", "lines" => [{"line": 12, "hits": 0, "covered": false}], plus "summary" with totals and "stale": "ok" | "missing" | "newer" | "length_mismatch" | "error".
        Example: "Show detailed coverage for lib/cov_loupe/model.rb".
      DESC
      input_schema(**input_schema_def)
      class << self
        def call(path:, root: nil, coverage_file: nil, resultset: nil, raise_on_stale: nil,
          error_mode: 'log', output_chars: nil, server_context:)
          call_with_file_payload(
            path:           path,
            error_mode:     error_mode,
            output_chars:   output_chars,
            server_context: server_context,
            root:           root,
            coverage_file:  coverage_file,
            resultset:      resultset,
            raise_on_stale: raise_on_stale
          )
        end
      end
    end
  end
end
