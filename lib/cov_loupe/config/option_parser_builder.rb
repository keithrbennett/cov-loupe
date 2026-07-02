# frozen_string_literal: true

require_relative 'option_normalizers'
require_relative '../version'
require_relative '../resources'
require_relative 'boolean_type'
require_relative '../errors/errors'

module CovLoupe
  class OptionParserBuilder
    HORIZONTAL_RULE = '-' * 79

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def build_option_parser
      require 'optparse'
      OptionParser.new do |parser|
        configure_banner(parser)
        define_environment_help(parser)
        define_subcommands_help(parser)
        define_options(parser)
        define_examples(parser)
      end
    end

    private def configure_banner(parser)
      parser.banner = <<~BANNER
        #{HORIZONTAL_RULE}
        Usage:                 cov-loupe [options] [subcommand] [args]  (default subcommand: list)
        Repository:            #{Resources::REPOSITORY_URL}
        Documentation (Web):   #{Resources::DOCUMENTATION_WEB_URL}
        Documentation (Local): #{Resources::LOCAL_README_PATH}
        Screencast:            #{Resources::SCREENCAST_URL}
        Version:               #{CovLoupe::VERSION}
        #{HORIZONTAL_RULE}

        BANNER
    end

    private def define_subcommands_help(parser)
      parser.separator <<~SUBCOMMANDS
        Subcommands:
          detailed, d <path>       Show per-line rows with hits/covered
          list, l                  Show files coverage (default: table, or use --format)
          raw, r <path>            Show the SimpleCov 'lines' array
          summary, s <path>        Show covered/total/% for a file
          totals, t                Show aggregated line totals and average %
          uncovered, u <path>      Show uncovered lines and a summary
          validate, v <file>       Evaluate coverage policy from file (exit 0=pass, 1=fail, 2=error)
          validate, v -i <code>    Evaluate coverage policy from code string

        SUBCOMMANDS
    end

    private def define_options(parser)
      parser.separator 'Options:'
      parser.on('-r', '--resultset PATH', String,
        'Path or directory that contains .resultset.json (default: coverage/.resultset.json)') \
      do |value|
        config.resultset = value
      end
      parser.on('-R', '--root PATH', String, 'Project root (default: .)') do |value|
        config.root = value
      end
      parser.on(
        '-f', '--format FORMAT', String,
        'Output format: a[mazing_print]|i[nspect]|j[son]|J (pretty_json)|p[uts]|' \
          'P (pretty_print)|t[able]|y[aml] (default: table)'
      ) do |value|
        config.format = normalize_format(value)
      end
      parser.on('-o', '--sort-order ORDER', String,
        'Sort order for list: a[scending]|d[escending] (default descending)') do |value|
        config.sort_order = normalize_sort_order(value)
      end
      parser.on('-s', '--source MODE', String,
        'Source display: f[ull]|u[ncovered]|n[one] (use none to disable)') do |value|
        config.source_mode = normalize_source_mode(value)
      end
      parser.on('-c', '--context-lines N', Integer,
        'Context lines around uncovered lines (non-negative, default: 2)') do |value|
        raise UsageError, 'Context lines cannot be negative' if value.negative?

        config.source_context = value
      end
      parser.on('-C', '--color BOOLEAN', BooleanType::IS_BOOLEAN_STRING_VALUE,
        'Enable/disable ANSI colors for source output (default: true). ' \
          "Accepts: #{BooleanType::BOOLEAN_VALUES_DISPLAY_STRING}") do |value|
        config.color = BooleanType.parse(value)
      end
      parser.on('-S', '--raise-on-stale BOOLEAN', BooleanType::IS_BOOLEAN_STRING_VALUE,
        'Raise error if coverage is stale (default: false). ' \
          "Accepts: #{BooleanType::BOOLEAN_VALUES_DISPLAY_STRING}") do |value|
        config.raise_on_stale = BooleanType.parse(value)
      end
      parser.on('-g', '--tracked-globs x,y,z', Array,
        'Used to exclude unwanted results and/or include files with or without coverage data',
        'Default: [] (shows all files in resultset)',
        'Best practice: match your SimpleCov track_files patterns',
        'Example: --tracked-globs lib/**/*.rb,app/**/*.rb') do |value|
        config.tracked_globs = value
      end
      parser.on('-h', '--help', 'Show help') do
        puts parser
        exit 0
      end
      parser.on('-l', '--log-file PATH', String,
        "Log file path (default ./cov_loupe.log, use 'stderr' for stream output, :off to disable)") do |value|
        config.log_file = value
      end
      parser.on('-m', '--mode MODE', String,
        'Execution mode: cli|mcp (default: cli)') do |value|
        config.mode = normalize_mode(value)
      end
      parser.on('-e', '--error-mode MODE', String,
        'Error handling mode: o[ff]|l[og]|d[ebug] (default: log)',
        '  off:   silent',
        '  log:   log errors to file',
        '  debug: verbose with backtraces') do |value|
        config.error_mode = normalize_error_mode(value)
      end
      parser.on('-O', '--output-chars MODE', String,
        'Output character mode: d[efault]|f[ancy]|a[scii] (default: default)',
        '  default: UTF-8 encoding uses fancy (Unicode), else ascii',
        '  fancy:   use Unicode box-drawing and symbols',
        '  ascii:   use ASCII-only characters (0x00-0x7F)') do |value|
        config.output_chars = normalize_output_chars(value)
      end
      parser.on('-v', '--version', 'Print version and exit.') do
        puts CovLoupe::VERSION
        exit 0
      end
      parser.on('-p', '--path-for NAME', String,
        'Print resource path/URL and exit. NAME: repo, docs, docs-local.') do |value|
        puts Resources.cli_url_for(value)
        exit 0
      rescue UsageError => e
        warn e.user_friendly_message
        exit 1
      end
    end

    private def define_environment_help(parser)
      parser.separator <<~ENVIRONMENT
        Environment:
          COV_LOUPE_OPTS can be used to set default options. Command-line arguments override these defaults.
          Example: export COV_LOUPE_OPTS="--format json --sort-order ascending"

      ENVIRONMENT
    end

    private def define_examples(parser)
      parser.separator <<~EXAMPLES

        Examples:
          cov-loupe --resultset coverage list
          cov-loupe --format json --resultset coverage summary lib/foo.rb
          cov-loupe --source uncovered --context-lines 2 uncovered lib/foo.rb
          cov-loupe totals --format json
        EXAMPLES
    end

    private def normalize_sort_order(value)
      OptionNormalizers.normalize_sort_order(value, strict: true)
    end

    private def normalize_source_mode(value)
      OptionNormalizers.normalize_source_mode(value, strict: true)
    end

    private def normalize_error_mode(value)
      OptionNormalizers.normalize_error_mode(value, strict: true)
    end

    private def normalize_format(value)
      OptionNormalizers.normalize_format(value, strict: true)
    end

    private def normalize_mode(value)
      OptionNormalizers.normalize_mode(value, strict: true)
    end

    private def normalize_output_chars(value)
      OptionNormalizers.normalize_output_chars(value, strict: true)
    end
  end
end
