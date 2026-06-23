# frozen_string_literal: true

require_relative 'app_config'
require_relative 'option_parser_builder'

module CovLoupe
  # Parses command-line arguments into an AppConfig.
  #
  # Used in both CLI and MCP modes to extract mode, log file, and other global
  # settings before dispatching to the appropriate runner. Uses order! so that
  # subcommand-specific options (e.g., 'validate -i') are not consumed by the
  # global parser.
  class ConfigParser
    attr_reader :config, :argv

    def initialize(argv)
      @argv = argv
      @config = AppConfig.new
    end

    # Parse argv (with env opts already merged) and return config
    # @param argv [Array<String>] command-line arguments (should include env opts if needed)
    # @return [AppConfig] populated configuration object
    def self.parse(argv)
      new(argv).parse
    end

    def parse
      # Build and execute the option parser
      parser = OptionParserBuilder.new(config).build_option_parser

      # Use order! to stop at the first non-option argument (the subcommand).
      # This ensures that subcommand-specific options (like 'validate -i') are not
      # stripped by the global option parser.
      parser.order!(argv)

      config.validate!
    end
  end
end
