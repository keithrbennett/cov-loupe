# frozen_string_literal: true

require_relative 'base_command'
require_relative '../presenters/coverage_payload_presenter'
require_relative '../formatters/table_formatter'

module CovLoupe
  module Commands
    # @api private
    class RawCommand < BaseCommand
      def execute(args)
        handle_with_path(args, 'raw') do |path|
          presenter = Presenters::CoveragePayloadPresenter.new(model: model, path: path,
            payload_method: :raw_for)
          data = presenter.payload
          break if maybe_output_structured_format?(data)

          relative_path = presenter.relative_path
          puts "File: #{relative_path}"
          puts

          # Table format for raw coverage data
          headers = %w[Line Coverage]
          rows = data['lines'].each_with_index.map do |coverage, index|
            [
              (index + 1).to_s,
              coverage.nil? ? 'nil' : coverage.to_s,
            ]
          end

          puts TableFormatter.format(
            headers:      headers,
            rows:         rows,
            alignments:   %i[right right],
            output_chars: config.output_chars
          )
        end
      end
    end
  end
end
