# frozen_string_literal: true

require_relative '../file_tool'

module CovLoupe
  module Tools
    # @api private
    class FileCoverageDetailedTool < FileTool
      tool_name 'file_coverage_detailed'
      description <<~DESC
        Use this when the user needs per-line coverage data for a single file.
        Do not use this for high-level counts; file_coverage_summary is cheaper for aggregate numbers.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale/output_chars.
        Output: JSON object with "schema_version" (Integer), "file", "lines" => [{"line": 12, "hits": 0, "covered": false}], the line metrics "covered", "uncovered", "total", "percentage" (percentage is null if the file has no coverable lines), and "stale": "ok" | "deleted" | "newer" | "length_mismatch" | "unreadable".
        Example: "Show detailed coverage for lib/my_app/order.rb".
      DESC
    end
  end
end
