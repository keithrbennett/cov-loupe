# frozen_string_literal: true

require_relative 'app_config'
require_relative 'option_parser_builder'

module CovLoupe
  # Parses command-line arguments into an AppConfig.
  #
  # Options can come before and after the subcommand. parse_options parses the ones before it
  # with order!, stopping at the subcommand; parse_subcommand_options parses the arguments
  # after it with permute!, with the options allowed there plus the subcommand's own (only
  # validate's -i/--inline), leaving the positional arguments.
  #
  # @api private
  class ConfigParser
    attr_reader :config, :argv

    # argv is what parse and a parse_options call without arguments parse.
    def initialize(argv = [])
      @argv = argv
      @config = AppConfig.new
      @stopped_at_terminator = false
    end

    # Parses argv (the options before any subcommand) and returns the validated config.
    # COV_LOUPE_OPTS is not read here; a caller that wants it includes its arguments in argv.
    # @param argv [Array<String>] arguments to parse
    # @return [AppConfig] populated configuration object
    def self.parse(argv)
      new(argv).parse
    end

    def parse
      parse_options.validate!
    end

    # Parses the options before the subcommand from args (by default the argv given to new)
    # into config without validating the result, so a caller can parse in parts and tell parse
    # errors from validation errors. Parsed arguments are removed from args; parsing stops at
    # the first non-option argument (the subcommand) or at '--'.
    # @return [AppConfig]
    def parse_options(args = argv)
      parser = OptionParserBuilder.new(config).build_option_parser
      @stopped_at_terminator = false
      # Replaces OptionParser's own '--' handling (in OptionParser::DefaultList), which this
      # mirrors, to record that parsing stopped there: order! removes the '--', so args alone
      # cannot show it.
      parser.top.long[''] = OptionParser::Switch::NoArgument.new do
        @stopped_at_terminator = true
        parser.terminate
      end
      parser.order!(args)
      config
    end

    # Whether the last parse_options stopped at a '--' (as opposed to a '--' that was an
    # option's value).
    def stopped_at_terminator?
      @stopped_at_terminator
    end

    # Parses the arguments after the subcommand into config, without validating it. Options
    # and positional arguments may be mixed; a '--' ends the options. Parsed arguments are
    # removed from args, leaving the positional arguments in order.
    # @param subcommand [String] the subcommand's full name
    # @param args [Array<String>] the arguments after the subcommand
    # @return [String, nil] validate's inline code (-i), or nil
    def parse_subcommand_options(subcommand, args)
      parser = OptionParserBuilder.new(config).build_subcommand_option_parser
      inline_code = nil
      if subcommand == 'validate'
        parser.on('-i', '--inline CODE', String) { |value| inline_code = value }
      end
      parser.permute!(args)
      inline_code
    end
  end
end
