# frozen_string_literal: true

require_relative '../file_tool'

module CovLoupe
  module Tools
    # @api private
    class FileCoverageSummaryTool < FileTool
      tool_name 'file_coverage_summary'
      description <<~DESC
        Use this when the user asks for the covered/total line counts and percentage for a specific file.
        Do not use this for multi-file reports; use project_coverage for per-file listings or project_coverage_totals for aggregate totals.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale/output_chars.
        Output: JSON object {"schema_version": Integer, "file": String, "covered": Integer, "uncovered": Integer, "total": Integer, "percentage": Float | null, "stale": "ok" | "deleted" | "newer" | "length_mismatch" | "unreadable"}.
        Example: "What is the coverage for lib/my_app/order.rb?".
      DESC
    end
  end
end
