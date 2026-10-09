# frozen_string_literal: true

require_relative '../output_chars'
require_relative '../exit_codes'

module CovLoupe
  module OptionParsers
    class ErrorHelper
      def initialize(subcommands)
        @subcommands = subcommands
      end

      def handle_option_parser_error(error, argv: [], output_chars: :default,
        usage_hint: "Run '#{program_name} --help' for usage information.")
        message = convert_text(error.message.to_s, output_chars)
        # Suggest a subcommand when an invalid option matches a known subcommand
        option = extract_invalid_option(message)

        if option&.start_with?('--') && @subcommands.include?(option[2..])
          suggest_subcommand(option, output_chars)
        else
          # Generic message from OptionParser
          warn "Error: #{message}"
          # Attempt to derive a helpful hint for enumerated options
          if (hint = build_enum_value_hint(argv))
            warn hint
          end
        end
        warn usage_hint
        exit ExitCodes::USAGE
      end

      private def extract_invalid_option(message)
        message.match(/invalid option: (.+)/)[1]
      rescue
        nil
      end

      private def suggest_subcommand(option, output_chars)
        subcommand = option[2..]
        msg1 = convert_text("Error: '#{option}' is not a valid option. " \
          "Did you mean the '#{subcommand}' subcommand?", output_chars)
        msg2 = convert_text("Try: #{program_name} #{subcommand} [args]", output_chars)
        warn msg1
        warn msg2
      end

      private def convert_text(text, output_chars)
        OutputChars.convert(text, output_chars)
      end

      private def build_enum_value_hint(argv)
        rules = enumerated_option_rules
        tokens = Array(argv)
        rules.each do |rule|
          hint = build_hint_for_rule(rule, tokens)
          return hint if hint
        end
        nil
      end

      private def build_hint_for_rule(rule, tokens)
        switches = rule[:switches]
        allowed = rule[:values]
        display = rule[:display] || allowed.join(', ')
        preferred = switches.find { |s| s.start_with?('--') } || switches.first

        tokens.each_with_index do |tok, i|
          # --opt=value form
          if equal_form_match?(tok, switches, preferred)
            hint = handle_equal_form(tok, switches, preferred, display, allowed)
            return hint if hint
          end

          # --opt value or -o value form
          if switches.include?(tok)
            hint = handle_space_form(tokens, i, preferred, display, allowed)
            return hint if hint
          end
        end
        nil
      end

      private def equal_form_match?(token, switches, preferred)
        token.start_with?(preferred + '=') || switches.any? { |s| token.start_with?(s + '=') }
      end

      private def handle_equal_form(token, switches, preferred, display, allowed)
        sw = switches.find { |s| token.start_with?(s + '=') } || preferred
        val = token.split('=', 2)[1]
        "Valid values for #{sw}: #{display}" if val && !allowed.include?(val)
      end

      private def handle_space_form(tokens, index, preferred, display, allowed)
        val = tokens[index + 1]
        # If missing value, provide hint; if present and invalid, also hint
        if val.nil? || val.start_with?('-') || !allowed.include?(val)
          "Valid values for #{preferred}: #{display}"
        end
      end

      private def enumerated_option_rules
        [
          { switches: ['-s', '--source'], values: %w[full f uncovered u none n],
            display: 'f[ull]|u[ncovered]|n[one]' },
          { switches: ['--error-mode'], values: %w[off o log l debug d],
            display: 'o[ff]|l[og]|d[ebug]' },
          { switches: ['-o', '--sort-order'], values: %w[a d ascending descending],
            display: 'a[scending]|d[escending]' },
        ]
      end

      private def program_name
        'cov-loupe'
      end
    end
  end
end
