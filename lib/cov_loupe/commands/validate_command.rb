# frozen_string_literal: true

require_relative 'base_command'
require_relative '../config/predicate_evaluator'
require_relative '../exit_codes'

module CovLoupe
  module Commands
    # Validates coverage data against a predicate.
    # Exits with code 0 (pass) or 3 (validation failed). Errors, including PredicateError (4),
    # propagate to the CLI, which reports them and maps them to an exit code.
    #
    # Usage:
    #   cov-loupe validate policy.rb                # File mode
    #   cov-loupe validate -i '->(m) { ... }'       # Inline mode
    #
    # @api private
    class ValidateCommand < BaseCommand
      # The -i code is parsed with the options after the subcommand (see
      # ConfigParser#parse_subcommand_options); args holds only the positional arguments.
      def execute(args)
        code = cli.inline_code
        result = if code
          # A policy file, or any other argument, beside -i is unexpected.
          reject_extra_args(args, 'validate')
          PredicateEvaluator.evaluate_code(code, model)
        else
          file_path = args.shift or raise UsageError.for_subcommand('validate <file> | -i <code>')
          reject_extra_args(args, 'validate')
          PredicateEvaluator.evaluate_file(file_path, model)
        end

        raise CliExit, result ? ExitCodes::SUCCESS : ExitCodes::VALIDATION_FAILED
      end
    end
  end
end
