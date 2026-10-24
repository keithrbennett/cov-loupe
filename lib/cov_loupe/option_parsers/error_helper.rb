# frozen_string_literal: true

require_relative '../exit_codes'
require_relative '../config/option_normalizers'

module CovLoupe
  module OptionParsers
    # @api private
    class ErrorHelper
      def initialize(subcommands)
        @subcommands = subcommands
      end

      def handle_option_parser_error(error, argv: [],
        usage_hint: "Run '#{program_name} --help' for usage information.")
        message = error.message.to_s
        # Suggest a subcommand when an invalid option matches a known subcommand
        option = extract_invalid_option(message)

        if option&.start_with?('--') && @subcommands.include?(option[2..])
          suggest_subcommand(option)
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

      private def suggest_subcommand(option)
        subcommand = option[2..]
        warn "Error: '#{option}' is not a valid option. Did you mean the '#{subcommand}' subcommand?"
        warn "Try: #{program_name} #{subcommand} [args]"
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
          { switches: ['-e', '--error-mode'], values: %w[off o log l debug d],
            display: 'o[ff]|l[og]|d[ebug]' },
          { switches: ['-o', '--sort-order'], values: %w[a d ascending descending],
            display: 'a[scending]|d[escending]' },
          { switches: ['-O', '--output-chars'], values: OptionNormalizers::OUTPUT_CHARS_MAP.keys,
            display: 'd[efault]|f[ancy]|a[scii]' },
          { switches: ['-f', '--format'],
            values:   OptionNormalizers::FORMAT_LONG_NAMES.to_a.flatten,
            display:  OptionNormalizers.available_format_choices.join('|') },
        ]
      end

      private def program_name
        'cov-loupe'
      end
    end
  end
end
