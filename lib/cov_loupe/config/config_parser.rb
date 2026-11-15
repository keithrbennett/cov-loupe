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
  #
  # @api private
  class ConfigParser
    attr_reader :config, :argv

    # argv is what parse and a parse_options call without arguments parse.
    def initialize(argv = [])
      @argv = argv
      @config = AppConfig.new
      @options_ended = false
    end

    # Parses argv and returns the validated config. COV_LOUPE_OPTS is not read here; a caller
    # that wants it includes its arguments in argv.
    # @param argv [Array<String>] arguments to parse
    # @return [AppConfig] populated configuration object
    def self.parse(argv)
      new(argv).parse
    end

    def parse
      parse_options.validate!
    end

    # Parses options from args (by default the argv given to new) into config without
    # validating the result, so a caller can parse in parts and tell parse errors from
    # validation errors. Parsed arguments are removed from args.
    # @return [AppConfig]
    def parse_options(args = argv)
      # Build and execute the option parser
      parser = OptionParserBuilder.new(config).build_option_parser
      @options_ended = false
      # Replaces OptionParser's own '--' handling (in OptionParser::DefaultList), which this mirrors, to record that parsing
      # stopped there: order! removes the '--', so args alone cannot show it.
      parser.top.long[''] = OptionParser::Switch::NoArgument.new do
        @options_ended = true
        parser.terminate
      end

      # Use order! to stop at the first non-option argument (the subcommand).
      # This ensures that subcommand-specific options (like 'validate -i') are not
      # stripped by the global option parser.
      parser.order!(args)
      @options_ended ||= !args.empty?
      config
    end

    # Whether the last parse_options stopped at a non-option argument or '--', so that any
    # arguments after the ones it parsed are not options.
    def options_ended?
      @options_ended
    end
  end
end
