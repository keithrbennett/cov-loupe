# frozen_string_literal: true

require_relative 'base_command'
require_relative '../staleness/stale_status'

module CovLoupe
  module Commands
    # @api private
    class SummaryCommand < BaseCommand
      def execute(args)
        with_file_payload(args, 'summary', :summary_for) do |data, relative_path|
          rows = [[
            relative_path,
            format_percentage(data['percentage']),
            data['covered'].to_s,
            data['total'].to_s,
            StaleStatus.stale?(data['stale']) ? 'Yes' : '',
          ]]
          print_table(['File', '%', 'Covered', 'Total', 'Stale'], rows,
            %i[left right right right center])
          puts
        end
      end
    end
  end
end
