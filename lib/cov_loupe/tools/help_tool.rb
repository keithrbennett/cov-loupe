# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../resources'

module CovLoupe
  module Tools
    # @api private
    class HelpTool < BaseTool
      tool_name 'help'
      description <<~DESC
        Returns help describing the other registered tools, including: use_when, avoid_when, inputs.
        Also returns documentation resources (repo, docs, docs_local) under "resources".
      DESC

      input_schema(
        type:                 'object',
        additionalProperties: false,
        properties:           {
          output_chars: COMMON_PROPERTIES[:output_chars],
        }
      )

      # Every tool accepts these, so they are added to each entry's inputs.
      COMMON_INPUTS = ['output_chars (optional)'].freeze

      TOOL_GUIDE = [
        {
          tool:       FileCoverageSummaryTool,
          label:      'Single-file coverage summary',
          use_when:   'User wants covered/total line counts or percentage for one file.',
          avoid_when: 'User needs repo-wide stats or specific uncovered lines.',
          inputs:     ['path (required)', 'root/coverage_file/raise_on_stale (optional)'],
        },
        {
          tool:       FileUncoveredLinesTool,
          label:      'Uncovered line numbers',
          use_when:   'User asks which lines in a file still lack tests.',
          avoid_when: 'User only wants overall percentages or detailed per-line hit data.',
          inputs:     ['path (required)', 'root/coverage_file/raise_on_stale (optional)'],
        },
        {
          tool:       FileCoverageDetailedTool,
          label:      'Per-line coverage details',
          use_when:   'User needs per-line hit counts for a file.',
          avoid_when: 'User only wants totals or uncovered line numbers.',
          inputs:     ['path (required)', 'root/coverage_file/raise_on_stale (optional)'],
        },
        {
          tool:       FileCoverageRawTool,
          label:      'Raw SimpleCov line hit counts',
          use_when:   "User needs SimpleCov's unprocessed hit-count array for a file.",
          avoid_when: 'User wants per-line details or explanations (use file_coverage_detailed).',
          inputs:     ['path (required)', 'root/coverage_file/raise_on_stale (optional)'],
        },
        {
          tool:       ProjectCoverageTool,
          label:      'Project coverage (JSON, table, YAML, etc.)',
          use_when:   'User wants coverage data for every file in the coverage data (or every ' \
                      'file matching file_globs) in their preferred format.',
          avoid_when: 'User asks about a single file or only wants totals.',
          inputs:     ['root/coverage_file (optional)', 'sort_order', 'raise_on_stale', 'file_globs',
            'format (json/pretty_json/yaml/amazing_print/inspect/puts/pretty_print/table)'],
        },
        {
          tool:       ProjectCoverageTotalsTool,
          label:      'Project coverage totals',
          use_when:   'User wants total/covered/uncovered line counts or the overall coverage percent.',
          avoid_when: 'User needs per-file breakdowns.',
          inputs:     ['root/coverage_file (optional)', 'raise_on_stale', 'file_globs'],
        },
        {
          tool:       ProjectValidateTool,
          label:      'Validate coverage policy',
          use_when:   'User needs to enforce coverage rules (e.g., minimum percentage) in CI.',
          avoid_when: 'User just wants to view coverage data.',
          inputs:     ['code OR file (one required)', 'root/coverage_file/raise_on_stale (optional)'],
        },
        {
          tool:       VersionTool,
          label:      'cov-loupe --version',
          use_when:   'User needs to confirm the running gem version.',
          avoid_when: 'User is asking for coverage information.',
          inputs:     [],
        },
      ].freeze

      class << self
        def call(output_chars: nil, server_context:, **_unused)
          # Resolve (and validate) output_chars for formatting the successful result
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('HelpTool', server_context: server_context) do
            entries = TOOL_GUIDE
              .select { |guide| guide[:tool].available_in?(server_context) }
              .map { |guide| format_entry(guide) }

            respond_json({ tools: entries, resources: Resources.payload_map },
              output_chars: output_chars_sym)
          end
        end

        private def format_entry(guide)
          {
            'tool'       => guide[:tool].tool_name,
            'label'      => guide[:label],
            'use_when'   => guide[:use_when],
            'avoid_when' => guide[:avoid_when],
            'inputs'     => guide[:inputs] + COMMON_INPUTS,
          }
        end
      end
    end
  end
end
