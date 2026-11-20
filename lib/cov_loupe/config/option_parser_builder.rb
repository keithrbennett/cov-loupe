# frozen_string_literal: true

require_relative 'option_normalizers'
require_relative '../version'
require_relative '../resources'
require_relative 'boolean_type'
require_relative '../errors/errors'
require_relative '../exit_codes'
require_relative 'glob_list_splitter'

module CovLoupe
  # @api private
  class OptionParserBuilder
    HORIZONTAL_RULE = '-' * 79

    # Options that may come only before the subcommand. They select the mode, or print
    # something and exit, so they have no meaning for a subcommand.
    BEFORE_SUBCOMMAND_ONLY = %w[
      -h --help -m --mode -v --version -p --path-for
      --allow-code-predicates --no-allow-code-predicates
    ].freeze

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

    # A parser for the arguments after a subcommand: the global options that take values,
    # without help text and without the options in BEFORE_SUBCOMMAND_ONLY.
    def build_subcommand_option_parser
      require 'optparse'
      OptionParser.new do |parser|
        # OptionParser's built-in --help, --version and completion options would print and exit.
        parser.base.long.clear
        define_options(parser, after_subcommand: true)
      end
    end

    private def configure_banner(parser)
      parser.banner = <<~BANNER
        #{HORIZONTAL_RULE}
        Usage:                 cov-loupe [options] [subcommand] [options] [args]  (default subcommand: list)
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
          raw, r <path>            Show SimpleCov's per-line hit counts
          summary, s <path>        Show covered/total/% for a file
          totals, t                Show aggregated line totals and overall %
          uncovered, u <path>      Show uncovered lines and a summary
          validate, v <file>       Evaluate coverage policy from file (exit 0=pass, 1=data error, 3=fail, 4=bad predicate)
          validate, v -i <code>    Evaluate coverage policy from Ruby code that returns a callable (-i = --inline)

        SUBCOMMANDS
    end

    # With after_subcommand, the options in BEFORE_SUBCOMMAND_ONLY are left out.
    private def define_options(parser, after_subcommand: false)
      parser.separator 'Options:'
      parser.on('-c', '--coverage-file PATH', String,
        'Path to SimpleCov coverage.json, or to a directory containing it',
        '(default: coverage/coverage.json under the project root)') do |value|
        config.coverage_file = value
      end
      parser.on('-R', '--root PATH', String, 'Project root (default: .)') do |value|
        config.root = value
      end
      parser.on(
        '-f', '--format FORMAT', String,
        "Output format: #{OptionNormalizers.available_format_choices.join('|')} (default: table)"
      ) do |value|
        config.format = OptionNormalizers.normalize_format(value)
      end
      parser.on('-o', '--sort-order ORDER', String,
        "Sort order for list: #{OptionNormalizers.sort_order_choices} (default descending)") do |value|
        config.sort_order = OptionNormalizers.normalize_sort_order(value)
      end
      parser.on('-s', '--source MODE', String,
        'Source display: f[ull]|u[ncovered]|n[one] (default: none)') do |value|
        config.source_mode = OptionNormalizers.normalize_source_mode(value)
      end
      parser.on('-n', '--context-lines N', Integer,
        'Context lines around uncovered lines (non-negative, default: 2)') do |value|
        raise UsageError, 'Context lines cannot be negative' if value.negative?

        config.source_context = value
      end
      parser.on('-C', '--color BOOLEAN', BooleanType::IS_BOOLEAN_STRING_VALUE,
        'Enable/disable ANSI colors for source output (default: on when stdout is a terminal). ' \
          "Accepts: #{BooleanType::BOOLEAN_VALUES_DISPLAY_STRING}") do |value|
        config.color = BooleanType.parse(value)
      end
      parser.on('-S', '--raise-on-stale BOOLEAN', BooleanType::IS_BOOLEAN_STRING_VALUE,
        'Raise error if coverage is stale (default: false). For project queries, also raise',
        'if a file matching the file globs is not in coverage data, or if a row is skipped.',
        "Accepts: #{BooleanType::BOOLEAN_VALUES_DISPLAY_STRING}") do |value|
        config.raise_on_stale = BooleanType.parse(value)
      end
      # Not OptionParser's Array type: Array splits on every comma, which breaks brace patterns
      # such as 'app/{models,controllers}/**/*.rb' into two invalid globs. GlobListSplitter
      # splits only on commas outside {...} and [...]. Object passes the raw value through;
      # String would reject an empty value (-g ''), which Array accepted as no globs.
      parser.on('-g', '--file-globs PATTERNS', Object,
        'Limit project-level results (list, totals, default report, validate predicates) to',
        'files matching these comma-separated globs, and report matching files on disk that',
        'have no coverage data (e.g. files added since the last test run)',
        'In MCP mode, the default for project tools whose call passes no file_globs',
        'Default: [] (every file in the coverage file, as SimpleCov reported it)',
        'When set, use the files you expect covered, normally your SimpleCov cover globs',
        'Commas inside {...} or [...] belong to their pattern',
        'An unclosed {, or an unclosed [ outside braces, is an error',
        'Write a literal comma as [,], a literal [ as [[], and a literal { as a quoted \{ (not on Windows)',
        "Example: --file-globs 'lib/**/*.rb,app/{models,controllers}/**/*.rb'") do |value|
        config.file_globs = GlobListSplitter.split(value)
      end
      unless after_subcommand
        parser.on('-h', '--help', 'Show help (only before the subcommand)') do
          puts parser
          raise CliExit, ExitCodes::SUCCESS
        end
      end
      parser.on('-l', '--log-file PATH', String,
        'Log target (default stderr, use a file path for persistent logging, off to disable)') do |value|
        config.log_file = value
      end
      define_mode_options(parser) unless after_subcommand
      parser.on('-e', '--error-mode MODE', String,
        'Error handling mode: o[ff]|l[og]|d[ebug] (default: log)',
        '  off:   no error logging',
        '  log:   log errors to the log target (the CLI does not log them',
        '         to stderr, where it already prints them)',
        '  debug: as log, with full backtraces; the CLI also prints a backtrace') do |value|
        config.error_mode = OptionNormalizers.normalize_error_mode(value)
      end
      parser.on('-O', '--output-chars MODE', String,
        'Output character mode: d[efault]|f[ancy]|a[scii] (default: default)',
        '  default: UTF-8 encoding uses fancy (Unicode), else ascii',
        '  fancy:   draw tables and markers with Unicode characters',
        '  ascii:   draw tables and markers with ASCII; JSON escapes non-ASCII') do |value|
        config.output_chars = OptionNormalizers.normalize_output_chars(value)
      end
      define_exit_options(parser) unless after_subcommand
    end

    private def define_mode_options(parser)
      parser.on('-m', '--mode MODE', String,
        'Execution mode: c[li]|m[cp] (default: cli; only before the subcommand)') do |value|
        config.mode = OptionNormalizers.normalize_mode(value)
      end
      parser.on('--[no-]allow-code-predicates',
        'MCP mode: register the project_validate tool, which runs client-supplied',
        'Ruby with full process privileges (default: off; ignored in CLI mode;',
        'only before the subcommand)') do |value|
        config.allow_code_predicates = value
      end
    end

    private def define_exit_options(parser)
      parser.on('-v', '--version', 'Print version and exit (only before the subcommand).') do
        puts CovLoupe::VERSION
        raise CliExit, ExitCodes::SUCCESS
      end
      parser.on('-p', '--path-for NAME', String,
        'Print resource path/URL and exit (only before the subcommand).',
        'NAME: repo, docs, docs-local.') do |value|
        # An unknown NAME raises UsageError, which the caller reports like any other usage error.
        puts Resources.cli_url_for(value)
        raise CliExit, ExitCodes::SUCCESS
      end
    end

    private def define_environment_help(parser)
      parser.separator <<~ENVIRONMENT
        Environment:
          COV_LOUPE_OPTS can be used to set default options. Command-line arguments override these defaults.
          It may contain only options (no subcommand, arguments or standalone '--').
          Example: export COV_LOUPE_OPTS="--format json --sort-order ascending"

      ENVIRONMENT
    end

    private def define_examples(parser)
      parser.separator <<~EXAMPLES

        Options can come before or after the subcommand, except those marked
        "only before the subcommand". After the subcommand, a path starting with '-'
        must follow '--' (e.g. cov-loupe summary -- -odd.rb).

        Examples:
          cov-loupe list --coverage-file coverage
          cov-loupe summary lib/foo.rb --format json --coverage-file coverage
          cov-loupe uncovered lib/foo.rb --source uncovered --context-lines 2
          cov-loupe --format json totals
        EXAMPLES
    end
  end
end
