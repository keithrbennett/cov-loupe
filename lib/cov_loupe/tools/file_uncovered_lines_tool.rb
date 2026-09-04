# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../model/model'
require_relative '../presenters/coverage_payload_presenter'

module CovLoupe
  module Tools
    class FileUncoveredLinesTool < BaseTool
      tool_name 'file_uncovered_lines'
      description <<~DESC
        Use this when the user wants to know which lines in a file still lack coverage.
        Do not use this for overall percentages; coverage.summary is faster when counts are enough.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale flag inherited from BaseTool.
        Output: JSON object with keys "file", "uncovered" (array of integers), "summary" {"covered","total","percentage"}, and "stale": "ok" | "missing" | "newer" | "length_mismatch" | "error".
        Example: "List uncovered lines for lib/cov_loupe/tools/file_coverage_summary_tool.rb".
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
