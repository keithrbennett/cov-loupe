# frozen_string_literal: true

require_relative 'base_command'
require_relative '../config/predicate_evaluator'
require_relative '../exit_codes'

module CovLoupe
  module Commands
    # Validates coverage data against a predicate.
    # Exits with code 0 (pass) or 3 (validation failed). Errors, including PredicateError (4),
    # propagate to the CLI, which logs them and maps them to an exit code.
    #
    # Usage:
    #   cov-loupe validate policy.rb                # File mode
    #   cov-loupe validate -i '->(m) { ... }'       # Inline mode
    class ValidateCommand < BaseCommand
      def execute(args)
        # Parse command-specific options
        inline_mode = false
        code = nil

        # Simple option parsing for -i/--inline flag
        while args.first&.start_with?('-')
          case args.first
          when '-i', '--inline'
            inline_mode = true
            args.shift
            code = args.shift or raise UsageError.for_subcommand('validate -i <code>')
          else
            raise UsageError, "Unknown option for validate: #{args.first}"
          end
        end

        # If not inline mode, expect a file path as positional argument
        unless inline_mode
          file_path = args.shift or raise UsageError.for_subcommand('validate <file> | -i <code>')
          code = file_path
        end

        # Ensure no extra arguments remain
        reject_extra_args(args, 'validate')

        # Evaluate the predicate
        result = if inline_mode
          PredicateEvaluator.evaluate_code(code, model)
        else
          PredicateEvaluator.evaluate_file(code, model)
        end

        exit(result ? ExitCodes::SUCCESS : ExitCodes::VALIDATION_FAILED)
      end
    end
  end
end
