# frozen_string_literal: true

require_relative 'base_command'
require_relative '../staleness/stale_status'

module CovLoupe
  module Commands
    # @api private
    class DetailedCommand < BaseCommand
      def execute(args)
        with_file_payload(args, 'detailed', :detailed_for) do |data, relative_path|
          print_coverage_heading(relative_path, data)
          puts "Stale: #{data['stale']}" if StaleStatus.stale?(data['stale'])
          puts

          if data['total'].zero?
            puts 'No coverable lines.'
          else
            rows = data['lines'].map do |r|
              [r['line'].to_s, r['hits'].to_s, r['covered'] ? 'yes' : 'no']
            end
            print_table(%w[Line Hits Covered], rows, %i[right right center])
          end
        end
      end
    end
  end
end
