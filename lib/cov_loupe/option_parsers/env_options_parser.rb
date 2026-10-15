# frozen_string_literal: true

require 'shellwords'
require_relative '../config/option_normalizers'

module CovLoupe
  module OptionParsers
    # @api private
    class EnvOptionsParser
      ENV_VAR = 'COV_LOUPE_OPTS'

      def initialize(env_var: ENV_VAR)
        @env_var = env_var
      end

      def parse_env_opts
        opts_string = ENV[@env_var]
        return [] unless opts_string && !opts_string.empty?

        begin
          Shellwords.split(opts_string)
        rescue ArgumentError => e
          raise CovLoupe::ConfigurationError, "Invalid #{@env_var} format: #{e.message}"
        end
      end

      def pre_scan_error_mode(argv, error_mode_normalizer: method(:normalize_error_mode))
        # Quick scan for --error-mode or -e to ensure early errors are logged correctly.
        # Scan in reverse so that the last occurrence (CLI) overrides earlier ones (ENV).
        i = argv.length - 1
        while i >= 0
          arg = argv[i]
          if %w[--error-mode -e].include?(arg) && argv[i + 1]
            return error_mode_normalizer.call(argv[i + 1])

          elsif arg.start_with?('--error-mode=')
            value = arg.split('=', 2)[1]
            return error_mode_normalizer.call(value)

          elsif arg.start_with?('-e') && arg.length > 2
            # Handle attached short option: -edebug
            value = arg[2..]
            return error_mode_normalizer.call(value)

          end

          i -= 1
        end
        nil
      rescue
        # Ignore errors during pre-scan; they'll be caught during actual parsing
        nil
      end

      private def normalize_error_mode(value)
        OptionNormalizers.normalize_error_mode(value, strict: false, default: :log)
      end
    end
  end
end
