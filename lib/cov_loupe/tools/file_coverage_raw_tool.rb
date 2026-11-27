# frozen_string_literal: true

require_relative '../file_tool'

module CovLoupe
  module Tools
    # @api private
    class FileCoverageRawTool < FileTool
      tool_name 'file_coverage_raw'
      description <<~DESC
        Use this when you need the raw SimpleCov per-line hit counts (its `lines` array) for a file as stored on disk ("ignored" markers become null).
        Do not use this for human-friendly explanations; choose file_coverage_detailed or file_coverage_summary instead.
        Inputs: file path (required) plus optional root/coverage_file/raise_on_stale/output_chars.
        Output: JSON object with "schema_version" (Integer), "file", "line_hits" (SimpleCov's `lines` array of integers/nulls, one per source line as recorded), and "stale": "ok" | "deleted" | "newer" | "length_mismatch" | "unreadable".
        Example: "Fetch the raw coverage array for spec/support/foo_helper.rb".
      DESC
    end
  end
end
