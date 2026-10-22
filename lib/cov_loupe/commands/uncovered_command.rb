# frozen_string_literal: true

require_relative 'base_command'
require_relative '../presenters/coverage_payload_presenter'
require_relative '../formatters/table_formatter'

module CovLoupe
  module Commands
    # @api private
    class UncoveredCommand < BaseCommand
      def execute(args)
        handle_with_path(args, 'uncovered') do |path|
          presenter = Presenters::CoveragePayloadPresenter.new(model: model, path: path,
            payload_method: :uncovered_for)
          data = presenter.payload
          break if emit_structured_format_with_optional_source?(data, model, path)

          relative_path = presenter.relative_path
          summary = data['summary']

          puts "File: #{relative_path}"
          puts "Coverage: #{format_percentage(summary['percentage'])} " \
               "(#{summary['covered']}/#{summary['total']} lines)"
          puts

          # Table format for uncovered lines
          uncovered_lines = data['uncovered']
          if summary['total'].zero?
            puts 'No coverable lines.'
          elsif uncovered_lines.empty?
            puts 'All lines covered!'
          else
            headers = ['Line']
            rows = uncovered_lines.map { |line| [line.to_s] }

            puts TableFormatter.format(
              headers:      headers,
              rows:         rows,
              alignments:   [:right],
              output_chars: config.output_chars
            )
          end

          puts
          print_source_for(model, path) if config.source_mode
        end
      end
    end
  end
end
