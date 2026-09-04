# frozen_string_literal: true

require_relative '../model/model'
require_relative '../base_tool'
require_relative '../presenters/project_totals_presenter'

module CovLoupe
  module Tools
    class ProjectCoverageTotalsTool < BaseTool
      tool_name 'project_coverage_totals'
      description <<~DESC
        Use this when you want aggregated coverage counts for the entire project.
        It reports covered/total lines, uncovered line counts, and the overall average percentage.
        Inputs: optional project root, alternate coverage file path, raise_on_stale flag, tracked_globs, and error mode.
        Output: JSON {"lines":{"total","covered","uncovered","percentage","included_files","excluded_files"},"tracking":{"enabled","globs"},"files":{"total","with_coverage","without_coverage"},"timestamp_status":"ok"|"missing","warnings":[string,...]}.
        When raise_on_stale is enabled, the tool will raise an error immediately if any files have coverage data errors or staleness issues.
        "timestamp_status" indicates whether coverage timestamps are available for time-based staleness checks. "warnings" array is present when timestamp_status is "missing".
        Example: "Give me total/covered/uncovered line counts and the overall coverage percent."
      DESC

      input_schema(**coverage_schema(
        additional_properties: {
          tracked_globs: TRACKED_GLOBS_PROPERTY,
        }
      ))

      class << self
        def call(root: nil, coverage_file: nil, resultset: nil, raise_on_stale: nil,
          tracked_globs: nil, error_mode: 'log', output_chars: nil, server_context:)
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('ProjectCoverageTotalsTool',
            error_mode: error_mode, output_chars: output_chars_sym) do
            model, config = create_configured_model(
              server_context: server_context,
              root:           root,
              coverage_file:  coverage_file,
              resultset:      resultset,
              raise_on_stale: raise_on_stale,
              tracked_globs:  tracked_globs
            )

            presenter = Presenters::ProjectTotalsPresenter.new(
              model:          model,
              raise_on_stale: config[:raise_on_stale],
              tracked_globs:  config[:tracked_globs]
            )
            payload = presenter.relativized_payload

            # Add warnings array if timestamp_status is missing
            if payload['timestamp_status'] == 'missing'
              payload['warnings'] = [
                'Coverage timestamps are missing. Time-based staleness checks were skipped.',
                'Files may appear "ok" even if source code is newer than the coverage data.',
                'Check your coverage tool configuration to ensure timestamps are recorded.',
              ]
            end

            respond_json(payload, name: 'coverage_totals.json', pretty: true,
              output_chars: output_chars_sym)
          end
        end
      end
    end
  end
end
