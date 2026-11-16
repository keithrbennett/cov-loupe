# frozen_string_literal: true

require 'shellwords'

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
    end
  end
end
