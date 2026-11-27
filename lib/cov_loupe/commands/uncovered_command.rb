# frozen_string_literal: true

require_relative 'base_command'

module CovLoupe
  module Commands
    # @api private
    class UncoveredCommand < BaseCommand
      def execute(args)
        with_file_payload(args, 'uncovered', :uncovered_for) do |data, relative_path|
          print_coverage_heading(relative_path, data)
          puts

          uncovered_lines = data['uncovered_lines']
          if data['total'].zero?
            puts 'No coverable lines.'
          elsif uncovered_lines.empty?
            puts 'All lines covered!'
          else
            print_table(['Line'], uncovered_lines.map { |line| [line.to_s] }, [:right])
          end
          puts
        end
      end
    end
  end
end
