# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../presenters/project_coverage_presenter'
require_relative '../config/option_normalizers'
require_relative '../output_chars'
require_relative '../formatters/formatters'
require_relative '../formatters/coverage_warnings'

module CovLoupe
  module Tools
    # @api private
    class ProjectCoverageTool < BaseTool
      tool_name 'project_coverage'
      description <<~DESC
        Use this when the user wants project-wide coverage data in their preferred format.
        Provides coverage percentages for every file in the coverage data (or matching file_globs) in JSON (default), or formatted output
        (table, YAML, pretty JSON, Amazing Print, inspect, puts, pretty_print).
        Inputs: optional project root, alternate coverage file path, sort order, raise_on_stale flag,
        file_globs, output_chars, and format (default: json).
        Output format depends on the format parameter:
        - json (default): JSON object with schema_version, files, skipped_files, etc.
          Each file row has "file", "covered", "uncovered", "total", "percentage", and "stale";
          "percentage" is null if the file has no coverable lines. An optional "warnings" array
          appears when timestamps are missing or most files were not found under the project root.
        - pretty_json: Multi-line, indented JSON
        - yaml: YAML format
        - amazing_print: Ruby object formatting via AmazingPrint
        - inspect: Ruby object#inspect output
        - puts: Ruby Kernel#puts output
        - pretty_print: Ruby stdlib PP.pp output
        - table: Plain text table with headers and percentages (matching CLI --format table)
        Files are listed highest coverage first by default; pass sort_order "ascending" to list
        the worst-covered files first, so they survive if a long result is cut short.
        Examples: "Show repo coverage"; "List files with lowest coverage"; "Get coverage as YAML".
      DESC
      input_schema(**coverage_schema(
        additional_properties: {
          sort_order: SORT_ORDER_PROPERTY,
          file_globs: FILE_GLOBS_PROPERTY,
          format:     {
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
          raise_on_stale: nil, file_globs: nil, format: 'json',
          output_chars: nil, server_context:)
          with_model(server_context: server_context, output_chars: output_chars, root: root,
            coverage_file: coverage_file, raise_on_stale: raise_on_stale,
            file_globs: file_globs) do |model, config, output_chars_sym|
            sort_order_sym = OptionNormalizers.normalize_sort_order(
              sort_order || BaseTool::DEFAULT_SORT_ORDER
            )

            format_sym = OptionNormalizers.normalize_format(format || 'json')

            presenter = Presenters::ProjectCoveragePresenter.new(
              model:          model,
              sort_order:     sort_order_sym,
              raise_on_stale: config[:raise_on_stale],
              file_globs:     config[:file_globs]
            )

            if format_sym == :table
              respond_with_table(presenter, output_chars_sym)
            else
              respond_with_formatted_payload(presenter, format_sym, output_chars_sym)
            end
          end
        end

        private def respond_with_table(presenter, output_chars_sym)
          table = presenter.format_table(output_chars: output_chars_sym)

          table += Formatters::CoverageWarnings.exclusions_summary(presenter)
          table += Formatters::CoverageWarnings.timestamp_warning(presenter)
          table += Formatters::CoverageWarnings.skipped_rows_warning(presenter)
          table += Formatters::CoverageWarnings.root_warning(presenter)

          respond_text(table)
        end

        private def respond_with_formatted_payload(presenter, format_sym, output_chars_sym)
          payload = Formatters::CoverageWarnings.payload_with_warnings(presenter)
          formatted = Formatters.format(PayloadSchema.add(payload), format_sym,
            output_chars: output_chars_sym)
          respond_text(formatted)
        end
      end
    end
  end
end
