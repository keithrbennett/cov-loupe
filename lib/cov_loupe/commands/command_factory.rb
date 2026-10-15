# frozen_string_literal: true

require_relative 'base_command'
require_relative 'list_command'
require_relative 'summary_command'
require_relative 'raw_command'
require_relative 'uncovered_command'
require_relative 'detailed_command'
require_relative 'totals_command'
require_relative 'validate_command'

module CovLoupe
  module Commands
    # Factory that maps subcommand names to their command classes.
    # Validates the command name and raises UsageError with the full usage
    # synopsis if the command is unknown.
    #
    # @api private
    class CommandFactory
      COMMAND_MAP = {
        'list'      => ListCommand,
        'summary'   => SummaryCommand,
        'raw'       => RawCommand,
        'uncovered' => UncoveredCommand,
        'detailed'  => DetailedCommand,
        'totals'    => TotalsCommand,
        'validate'  => ValidateCommand,
      }.freeze

      def self.create(command_name, cli_context)
        command_class = COMMAND_MAP[command_name]
        unless command_class
          raise UsageError.for_subcommand(
            'list | summary <path> | raw <path> | uncovered <path> | detailed <path> ' \
              '| totals | validate <file> | validate -i <code>'
          )
        end

        command_class.new(cli_context)
      end

      def self.available_commands
        COMMAND_MAP.keys
      end
    end
  end
end
