# frozen_string_literal: true

require_relative 'base_command'

module CovLoupe
  module Commands
    # @api private
    class RawCommand < BaseCommand
      def execute(args)
        with_file_payload(args, 'raw', :raw_for, source: false) do |data, relative_path|
          puts "File: #{relative_path}"
          puts

          rows = data['line_hits'].each_with_index.map do |coverage, index|
            [(index + 1).to_s, coverage.nil? ? 'nil' : coverage.to_s]
          end
          print_table(%w[Line Hits], rows, %i[right right])
        end
      end
    end
  end
end
