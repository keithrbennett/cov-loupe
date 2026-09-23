# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../presenters/project_coverage_presenter'
require_relative '../config/option_normalizers'
require_relative '../output_chars'
require_relative '../formatters/formatters'
require_relative '../formatters/coverage_warnings'

module CovLoupe
  module Tools
    class ProjectCoverageTool < BaseTool
      tool_name 'project_coverage'
      description <<~DESC
        Use this when the user wants project-wide coverage data in their preferred format.
        Provides coverage percentages for every tracked file in JSON (default), or formatted output
        (table, YAML, pretty JSON, Amazing Print, inspect, puts, pretty_print).
        Inputs: optional project root, alternate coverage file path, sort order, raise_on_stale flag,
        tracked_globs, output_chars, and format (default: json).
        Output format depends on the format parameter:
        - json (default): JSON object with files, counts, skipped_files, etc.
        - pretty_json: Multi-line, indented JSON
        - yaml: YAML format
        - amazing_print: Ruby object formatting via AmazingPrint
        - inspect: Ruby object#inspect output
        - puts: Ruby Kernel#puts output
        - pretty_print: Ruby stdlib PP.pp output
        - table: Plain text table with headers and percentages (matching CLI --format table)
        Examples: "Show repo coverage"; "List files with lowest coverage"; "Get coverage as YAML".
      DESC
      input_schema(**coverage_schema(
        additional_properties: {
          sort_order:    SORT_ORDER_PROPERTY,
          tracked_globs: TRACKED_GLOBS_PROPERTY,
          format:        {
            type:        'string',
            description: 'Output format (default: json). Accepts a short code or its canonical ' \
                         "long name: #{OptionNormalizers.available_format_choices.join(', ')}.",
            default:     'json',
            enum:        OptionNormalizers::FORMAT_LONG_NAMES.flat_map do |long_name, code|
              [code, long_name]
            end,
          },
        }
      ))
      class << self
        def call(root: nil, coverage_file: nil, sort_order: nil,
          raise_on_stale: nil, tracked_globs: nil, format: 'json', error_mode: 'log',
          output_chars: nil, server_context:)
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('ProjectCoverageTool',
            error_mode: error_mode, output_chars: output_chars_sym) do
            model, config = create_configured_model(
              server_context: server_context,
              root:           root,
              coverage_file:  coverage_file,
              raise_on_stale: raise_on_stale,
              tracked_globs:  tracked_globs
            )

            sort_order_sym = OptionNormalizers.normalize_sort_order(
              sort_order || BaseTool::DEFAULT_SORT_ORDER, strict: true
            )

            format_sym = OptionNormalizers.normalize_format(format || 'json', strict: true)

            presenter = Presenters::ProjectCoveragePresenter.new(
              model:          model,
              sort_order:     sort_order_sym,
              raise_on_stale: config[:raise_on_stale],
              tracked_globs:  config[:tracked_globs]
            )

            if format_sym == :table
              respond_with_table(presenter, model, sort_order_sym, config, output_chars_sym)
            else
              respond_with_formatted_payload(presenter, format_sym, output_chars_sym)
            end
          end
        end

        private def respond_with_table(presenter, model, sort_order_sym, config, output_chars_sym)
          file_summaries = presenter.relative_files
          table = model.format_table(
            file_summaries,
            sort_order:     sort_order_sym,
            raise_on_stale: config[:raise_on_stale],
            tracked_globs:  nil,
            output_chars:   output_chars_sym
          )

          table += Formatters::CoverageWarnings.exclusions_summary(presenter, output_chars_sym)
          table += Formatters::CoverageWarnings.timestamp_warning(presenter)
          table += Formatters::CoverageWarnings.skipped_rows_warning(presenter, output_chars_sym)

          ::MCP::Tool::Response.new([{ 'type' => 'text', 'text' => table }])
        end

        private def respond_with_formatted_payload(presenter, format_sym, output_chars_sym)
          payload = presenter.relativized_payload

          if payload['timestamp_status'] == 'missing'
            payload['warnings'] = Formatters::CoverageWarnings::TIMESTAMP_WARNING_LINES.dup
          end

          formatted = Formatters.format(payload, format_sym, output_chars: output_chars_sym)
          ::MCP::Tool::Response.new([{ 'type' => 'text', 'text' => formatted }])
        end
      end
    end
  end
end
