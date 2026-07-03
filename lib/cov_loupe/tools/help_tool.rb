# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../resources'

module CovLoupe
  module Tools
    class HelpTool < BaseTool
      tool_name 'help'
      description <<~DESC
        Returns help containing descriptions of all tools, including: use_when, avoid_when, inputs.
      DESC

      input_schema(
        type:                 'object',
        additionalProperties: false,
        properties:           {
          error_mode:   ERROR_MODE_PROPERTY,
          output_chars: COMMON_PROPERTIES[:output_chars],
        }
      )

      TOOL_GUIDE = [
        {
          tool:       FileCoverageSummaryTool,
          label:      'Single-file coverage summary',
          use_when:   'User wants covered/total line counts or percentage for one file.',
          avoid_when: 'User needs repo-wide stats or specific uncovered lines.',
          inputs:     ['path (required)', 'root/resultset/raise_on_stale (optional)'],
        },
        {
          tool:       FileUncoveredLinesTool,
          label:      'Uncovered line numbers',
          use_when:   'User asks which lines in a file still lack tests.',
          avoid_when: 'User only wants overall percentages or detailed per-line hit data.',
          inputs:     ['path (required)', 'root/resultset/raise_on_stale (optional)'],
        },
        {
          tool:       FileCoverageDetailedTool,
          label:      'Per-line coverage details',
          use_when:   'User needs per-line hit counts for a file.',
          avoid_when: 'User only wants totals or uncovered line numbers.',
          inputs:     ['path (required)', 'root/resultset/raise_on_stale (optional)'],
        },
        {
          tool:       FileCoverageRawTool,
          label:      'Raw SimpleCov lines array',
          use_when:   'User needs the raw SimpleCov `lines` array for a file.',
          avoid_when: 'User expects human-friendly summaries or explanations.',
          inputs:     ['path (required)', 'root/resultset/raise_on_stale (optional)'],
        },
        {
          tool:       ProjectCoverageTool,
          label:      'Project coverage (JSON, table, YAML, etc.)',
          use_when:   'User wants coverage data for every tracked file in their preferred format.',
          avoid_when: 'User asks about a single file or only wants totals.',
          inputs:     ['root/resultset (optional)', 'sort_order', 'raise_on_stale', 'tracked_globs',
            'format (json/pretty_json/yaml/amazing_print/inspect/puts/pretty_print/table)'],
        },
        {
          tool:       ProjectCoverageTotalsTool,
          label:      'Project coverage totals',
          use_when:   'User wants total/covered/uncovered line counts or the average percent.',
          avoid_when: 'User needs per-file breakdowns.',
          inputs:     ['root/resultset (optional)', 'raise_on_stale', 'tracked_globs'],
        },
        {
          tool:       ProjectValidateTool,
          label:      'Validate coverage policy',
          use_when:   'User needs to enforce coverage rules (e.g., minimum percentage) in CI.',
          avoid_when: 'User just wants to view coverage data.',
          inputs:     ['code OR file (one required)', 'root/resultset/raise_on_stale (optional)'],
        },
        {
          tool:       VersionTool,
          label:      'cov-loupe --version',
          use_when:   'User needs to confirm the running gem version.',
          avoid_when: 'User is asking for coverage information.',
          inputs:     ['(no arguments)'],
        },
      ].freeze

      class << self
        def call(error_mode: 'log', output_chars: nil, server_context:, **_unused)
          # Normalize output_chars before error handling so errors also get converted
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('HelpTool', error_mode: error_mode, output_chars: output_chars_sym) do
            entries = TOOL_GUIDE.map { |guide| format_entry(guide) }

            respond_json({ tools: entries, resources: Resources::RESOURCE_MAP }, name: 'tools_help.json',
              output_chars: output_chars_sym)
          end
        end

        private def format_entry(guide)
          {
            'tool'       => guide[:tool].tool_name,
            'label'      => guide[:label],
            'use_when'   => guide[:use_when],
            'avoid_when' => guide[:avoid_when],
            'inputs'     => guide[:inputs],
          }
        end
      end
    end
  end
end
