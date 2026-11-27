# frozen_string_literal: true

require_relative '../file_tool'

module CovLoupe
  module Tools
    # @api private
    class FileUncoveredLinesTool < FileTool
      tool_name 'file_uncovered_lines'
      description <<~DESC
        Use this when the user wants to know which lines in a file still lack coverage.
        Do not use this for overall percentages; file_coverage_summary is faster when counts are enough.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale/output_chars.
        Output: JSON object with keys "schema_version" (Integer), "file", "uncovered_lines" (array of line numbers), the line metrics "covered", "uncovered" (a count), "total", "percentage" (percentage is null if the file has no coverable lines), and "stale": "ok" | "deleted" | "newer" | "length_mismatch" | "unreadable".
        Example: "List uncovered lines for lib/my_app/order.rb".
      DESC
    end
  end
end
