# frozen_string_literal: true

require_relative '../model/model'
require_relative '../base_tool'
require_relative '../presenters/project_totals_presenter'
require_relative '../formatters/coverage_warnings'

module CovLoupe
  module Tools
    # @api private
    class ProjectCoverageTotalsTool < BaseTool
      tool_name 'project_coverage_totals'
      description <<~DESC
        Use this when you want aggregated coverage counts for the entire project.
        It reports covered/total lines, uncovered line counts, and the overall percentage (covered lines / coverable lines across included, non-stale files).
        Inputs: optional project root, alternate coverage file path, raise_on_stale flag, file_globs, error mode, and output_chars.
        Output: JSON {"schema_version":Integer,"covered","uncovered","total","percentage","file_globs":[string,...],"file_counts":{"total","with_coverage","without_coverage"?},"timestamp_status":"ok"|"missing","warnings"?:[string,...]}.
        The line metrics ("covered", "uncovered", "total", "percentage") count only fresh files; file_counts.with_coverage.ok is how many.
        "without_coverage" is present only when file_globs are set; "warnings" only when timestamp_status is "missing" or most files were not found under the project root.
        "percentage" is a number, or null when no lines are measurable (no coverable lines, or every file stale).
        When raise_on_stale is enabled, the tool will raise an error immediately if any files have coverage data errors or staleness issues.
        "timestamp_status" indicates whether coverage timestamps are available for time-based staleness checks.
        Example: "Give me total/covered/uncovered line counts and the overall coverage percent."
      DESC

      input_schema(**coverage_schema(
        additional_properties: {
          file_globs: FILE_GLOBS_PROPERTY,
        }
      ))

      class << self
        def call(root: nil, coverage_file: nil, raise_on_stale: nil,
          file_globs: nil, error_mode: nil, output_chars: nil, server_context:)
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('ProjectCoverageTotalsTool', error_mode: error_mode,
            server_context: server_context) do
            model, config = create_configured_model(
              server_context: server_context,
              root:           root,
              coverage_file:  coverage_file,
              raise_on_stale: raise_on_stale,
              file_globs:     file_globs
            )

            presenter = Presenters::ProjectTotalsPresenter.new(
              model:          model,
              raise_on_stale: config[:raise_on_stale],
              file_globs:     config[:file_globs]
            )
            payload = presenter.payload

            warnings = Formatters::CoverageWarnings.payload_warnings(presenter)
            payload['warnings'] = warnings if warnings.any?

            respond_json(payload, pretty: true, output_chars: output_chars_sym)
          end
        end
      end
    end
  end
end
