# frozen_string_literal: true

require_relative '../base_tool'
require_relative '../presenters/project_coverage_presenter'
require_relative '../config/option_normalizers'
require_relative '../output_chars'
require_relative '../formatters/formatters'

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
        def call(root: nil, coverage_file: nil, resultset: nil, sort_order: nil,
          raise_on_stale: nil, tracked_globs: nil, format: 'json', error_mode: 'log',
          output_chars: nil, server_context:)
          output_chars_sym = resolve_output_chars(output_chars, server_context)
          with_error_handling('ProjectCoverageTool',
            error_mode: error_mode, output_chars: output_chars_sym) do
            model, config = create_configured_model(
              server_context: server_context,
              root:           root,
              coverage_file:  coverage_file,
              resultset:      resultset,
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

          exclusions = format_exclusions_summary(presenter, output_chars_sym)
          table += exclusions unless exclusions.empty?

          timestamp_warning = format_timestamp_warning(presenter)
          table += timestamp_warning unless timestamp_warning.empty?

          skipped_warning = format_skipped_rows_warning(presenter, output_chars_sym)
          table += skipped_warning unless skipped_warning.empty?

          ::MCP::Tool::Response.new([{ 'type' => 'text', 'text' => table }])
        end

        private def respond_with_formatted_payload(presenter, format_sym, output_chars_sym)
          payload = presenter.relativized_payload

          if payload['timestamp_status'] == 'missing'
            payload['warnings'] = [
              'Coverage timestamps are missing. Time-based staleness checks were skipped.',
              'Files may appear "ok" even if source code is newer than the coverage data.',
              'Check your coverage tool configuration to ensure timestamps are recorded.',
            ]
          end

          formatted = Formatters.format(payload, format_sym, output_chars: output_chars_sym)
          ::MCP::Tool::Response.new([{ 'type' => 'text', 'text' => formatted }])
        end

        private def format_exclusions_summary(presenter, output_chars)
          missing = presenter.relative_missing_tracked_files
          newer = presenter.relative_newer_files
          deleted = presenter.relative_deleted_files
          length_mismatch = presenter.relative_length_mismatch_files
          unreadable = presenter.relative_unreadable_files
          skipped = presenter.relative_skipped_files

          return '' if missing.empty? && newer.empty? && deleted.empty? &&
            length_mismatch.empty? && unreadable.empty? && skipped.empty?

          convert_path = ->(path) { OutputChars.convert(path, output_chars) }

          output = ["\nFiles excluded from coverage:"]

          unless missing.empty?
            output << "\nMissing tracked files (#{missing.length}):"
            missing.each { |file| output << "  - #{convert_path.call(file)}" }
          end

          unless newer.empty?
            output << "\nFiles newer than coverage (#{newer.length}):"
            newer.each { |file| output << "  - #{convert_path.call(file)}" }
          end

          unless deleted.empty?
            output << "\nDeleted files with coverage (#{deleted.length}):"
            deleted.each { |file| output << "  - #{convert_path.call(file)}" }
          end

          unless length_mismatch.empty?
            output << "\nLine count mismatches (#{length_mismatch.length}):"
            length_mismatch.each { |file| output << "  - #{convert_path.call(file)}" }
          end

          unless unreadable.empty?
            output << "\nUnreadable files (#{unreadable.length}):"
            unreadable.each { |file| output << "  - #{convert_path.call(file)}" }
          end

          unless skipped.empty?
            output << "\nFiles skipped due to errors (#{skipped.length}):"
            skipped.each do |row|
              file_path = OutputChars.convert(row['file'], output_chars)
              error_msg = OutputChars.convert(row['error'], output_chars)
              output << "  - #{file_path}: #{error_msg}"
            end
          end

          output << "\nRun with --raise-on-stale to exit when files are excluded."
          output.join("\n")
        end

        private def format_timestamp_warning(presenter)
          return '' unless presenter.timestamp_status == 'missing'

          <<~WARNING

            WARNING: Coverage timestamps are missing. Time-based staleness checks were skipped.
            Files may appear "ok" even if source code is newer than the coverage data.
            Check your coverage tool configuration to ensure timestamps are recorded.
          WARNING
        end

        private def format_skipped_rows_warning(presenter, output_chars)
          skipped = presenter.relative_skipped_files
          return '' if skipped.nil? || skipped.empty?

          count = skipped.length
          output = [
            '',
            "WARNING: #{count} coverage row#{count == 1 ? '' : 's'} skipped due to errors:",
          ]
          skipped.each do |row|
            file_path = OutputChars.convert(row['file'], output_chars)
            error_msg = OutputChars.convert(row['error'], output_chars)
            output << "  - #{file_path}: #{error_msg}"
          end
          output << 'Run again with --raise-on-stale to exit when rows are skipped.'
          output.join("\n")
        end
      end
    end
  end
end
