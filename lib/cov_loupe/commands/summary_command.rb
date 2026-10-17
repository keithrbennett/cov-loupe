# frozen_string_literal: true

require_relative 'base_command'
require_relative '../presenters/coverage_payload_presenter'
require_relative '../formatters/table_formatter'
require_relative '../staleness/stale_status'

module CovLoupe
  module Commands
    # @api private
    class SummaryCommand < BaseCommand
      def execute(args)
        handle_with_path(args, 'summary') do |path|
          presenter = Presenters::CoveragePayloadPresenter.new(model: model, path: path,
            payload_method: :summary_for)
          data = presenter.payload
          break if emit_structured_format_with_optional_source?(data, model, path)

          relative_path = convert_text(presenter.relative_path)
          summary = data['summary']

          # Table format with box-drawing
          headers = ['File', '%', 'Covered', 'Total', 'Stale']
          stale_marker = StaleStatus.stale?(data['stale']) ? 'Yes' : ''

          rows = [[
            relative_path,
            format_percentage(summary['percentage']),
            summary['covered'].to_s,
            summary['total'].to_s,
            stale_marker,
          ]]

          puts TableFormatter.format(
            headers:      headers,
            rows:         rows,
            alignments:   %i[left right right right center],
            output_chars: config.output_chars
          )
          puts
          print_source_for(model, path) if config.source_mode
        end
      end
    end
  end
end
