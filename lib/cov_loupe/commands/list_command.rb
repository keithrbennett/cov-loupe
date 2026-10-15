# frozen_string_literal: true

require_relative 'base_command'

module CovLoupe
  module Commands
    # @api private
    class ListCommand < BaseCommand
      def execute(args)
        reject_extra_args(args, 'list')
        cli.send(:show_default_report, sort_order: config.sort_order)
      end
    end
  end
end
