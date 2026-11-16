# frozen_string_literal: true

require 'json'
require 'time'
require 'pathname'
require 'optparse'

require_relative 'cov_loupe/version'
require_relative 'cov_loupe/exit_codes'
require_relative 'cov_loupe/config/app_config'
require_relative 'cov_loupe/config/app_context'
require_relative 'cov_loupe/errors/errors'
require_relative 'cov_loupe/errors/error_handler'
require_relative 'cov_loupe/errors/error_handler_factory'
require_relative 'cov_loupe/paths/path_relativizer'
require_relative 'cov_loupe/model/model'
require_relative 'cov_loupe/coverage/coverage_reporter'

# CovLoupe: A Ruby gem for inspecting SimpleCov test coverage data.
#
# Architecture overview:
#   - Dual-mode entry point (CovLoupe.run): dispatches to CLI or MCP server based on --mode flag
#   - CoverageModel: domain layer that queries coverage data, delegates staleness and path resolution
#   - CoverageCLI / MCPServer: presentation layer (CLI commands vs JSON-RPC tool calls)
#   - CoverageRepository: data access layer (reads coverage.json, normalizes paths)
#   - ModelDataCache: singleton cache that auto-invalidates when the coverage file changes
#   - Presenters: memoized adapters that shape model payloads for CLI and MCP output
#
# Data flow for a typical request:
#   1. CoverageJsonLoader reads coverage.json
#   2. CoverageRepository normalizes keys to absolute paths
#   3. ModelDataCache stores the resulting ModelData (coverage_map, timestamp, recorded_root)
#   4. CoverageModel queries the cache and applies staleness/glob filters
#   5. Presenters wrap the model output (already project-relative) for display
#   6. CLI commands or MCP tools format the presenter output for the user
#
module CovLoupe
  class << self
    # === Context Management and Thread Safety ===
    #
    # CovLoupe manages configuration (logging, error handling) via `AppContext` objects.
    # The resolution strategy is:
    # 1. Fiber-local: Use `Thread.current[:cov_loupe_context]` if set.
    # 2. Global default: Fall back to `@internal_default_context`.
    #
    # This design supports both simple CLI usage (one global context) and multi-threaded
    # library usage (per-thread contexts; a new Fiber starts with none).
    #
    # Thread Safety:
    # - `mutex` protects all reads/writes to `@internal_default_context`.
    # - `default_log_file=` atomically updates the global default. Threads using the
    #   default (no fiber-local context) will immediately see the new value.
    # - `active_log_file=` creates or updates a *fiber-local* context, isolating
    #   changes to the current fiber.
    #
    # This separation ensures that changing the global default is safe and predictable,
    # while allowing threads to diverge when necessary without race conditions.

    THREAD_CONTEXT_KEY = :cov_loupe_context
    private_constant :THREAD_CONTEXT_KEY

    # Primary entry point. Parses argv to determine mode (CLI or MCP server),
    # then dispatches accordingly. Options from COV_LOUPE_OPTS are parsed first,
    # so the command line's options take precedence.
    #
    # Ends the process with an ExitCodes status when an option is invalid, after --help,
    # --version, or --path-for, and in CLI mode when a command fails and after validate. MCP
    # tool failures are isError results instead. Use execute to get the status without exiting.
    #
    # @param argv [Array<String>] command-line arguments
    # @return [Integer] ExitCodes::SUCCESS when it returns
    # @api public
    def run(argv)
      dispatch(argv)
      ExitCodes::SUCCESS
    end

    # Runs like run, but returns the exit status instead of ending the process. Only cov-loupe's
    # own exits are caught; an exit from elsewhere, such as a validate predicate, still ends it.
    #
    # @param argv [Array<String>] command-line arguments
    # @return [Integer] an ExitCodes status
    # @api public
    def execute(argv)
      run(argv)
    rescue CliExit => e
      e.status
    end

    private def dispatch(argv)
      # Parse config to determine mode
      require_relative 'cov_loupe/config/config_parser'

      env_argv, cli_argv = global_argv(argv)
      config, rest, global_args = parse_global_options(env_argv, cli_argv)

      if config.mode == :cli
        # CLI mode: load CLI components only
        require_relative 'cov_loupe/loaders/all_cli'
        CoverageCLI.new.run(rest, config: config, global_args: global_args)
      else
        # MCP server mode: load MCP server components only
        require_relative 'cov_loupe/loaders/all_mcp'

        handler = ErrorHandlerFactory.for_mcp_server(error_mode: config.error_mode)
        context = create_context(error_handler: handler, log_target: config.log_file,
          mode: :mcp, app_config: config)
        with_context(context) { MCPServer.new(context: context).run }
      end
    end

    # Temporarily sets the current thread's context for the duration of the block,
    # restoring the previous context afterward. The context is stored in Thread.current,
    # so it is fiber-local: a new Fiber does not see it. Used to scope logging and
    # error handling to a specific mode (CLI, MCP, library).
    #
    # @api public
    def with_context(context)
      previous = Thread.current[THREAD_CONTEXT_KEY]
      Thread.current[THREAD_CONTEXT_KEY] = context
      yield
    ensure
      Thread.current[THREAD_CONTEXT_KEY] = previous
    end

    # @api private
    def context
      Thread.current[THREAD_CONTEXT_KEY] || default_context
    end

    # Only log_target: is public. The error_handler:, mode:, and app_config: keywords are
    # internal; library code raises exceptions and never consults the context's handler.
    #
    # @api public
    def create_context(error_handler: nil, log_target: nil, mode: :library, app_config: nil)
      AppContext.new(
        error_handler: error_handler || ErrorHandlerFactory.for_library,
        log_target:    log_target.nil? ? default_context.log_target : log_target,
        mode:          mode,
        app_config:    app_config
      )
    end

    # @api public
    def default_log_file
      default_context.log_target
    end

    # @api public
    def default_log_file=(value)
      AppConfig.validate_log_file!(value)
      mutex.synchronize do
        previous_default = internal_default_context
        @internal_default_context = previous_default.with(log_target: value)
      end
      value # rubocop:disable Lint/Void -- Setter should return assigned value for direct calls.
    end

    # @api public
    def active_log_file
      context.log_target
    end

    # @api public
    def active_log_file=(value)
      AppConfig.validate_log_file!(value)
      current = Thread.current[THREAD_CONTEXT_KEY]
      Thread.current[THREAD_CONTEXT_KEY] = if current
        current.with(log_target: value)
      else
        base = mutex.synchronize { internal_default_context }
        base.with(log_target: value)
      end
    end

    # @api private
    def error_handler
      context.error_handler
    end

    # @api private
    def error_handler=(handler)
      mutex.synchronize do
        previous_default = internal_default_context
        @internal_default_context = previous_default.with(error_handler: handler)
      end
    end

    # @api private
    def logger
      context.logger
    end

    # Returns true if running on Windows (mingw, mswin, cygwin).
    #
    # @api private
    def windows?
      return @windows if defined?(@windows)

      @windows = RUBY_PLATFORM.match?(/mingw|mswin|cygwin/)
    end

    # @api public
    def version
      VERSION
    end

    private def mutex
      @mutex ||= Mutex.new
    end

    private def default_context
      mutex.synchronize { internal_default_context }
    end

    private def internal_default_context
      @internal_default_context ||= AppContext.new(
        error_handler: ErrorHandlerFactory.for_library,
        log_target:    nil,
        mode:          :library
      )
    end

    # Under a non-UTF-8 locale (LANG=C), arguments arrive tagged BINARY or US-ASCII, and a
    # non-ASCII path in them never equals the UTF-8 paths in coverage.json. Retag such arguments
    # when their bytes are valid UTF-8. Arguments in a real locale encoding (such as ISO-8859-1)
    # are left alone, because relabelling their bytes would change their characters.
    private def utf8_arg(arg)
      # ASCII-only arguments are retagged too: `-R .` expands to a path in the current directory.
      return arg unless arg.is_a?(String) && [Encoding::BINARY, Encoding::US_ASCII].include?(arg.encoding)

      utf8 = arg.dup.force_encoding(Encoding::UTF_8)
      utf8.valid_encoding? ? utf8 : arg
    end

    # An argument whose bytes are invalid in its encoding (such as a file name that is not UTF-8)
    # makes OptionParser and path handling raise ArgumentError, which reaches the user as a
    # backtrace or an "unexpected error". Reject it up front with a message that names it.
    private def validate_arg_encoding(arg)
      return if !arg.is_a?(String) || arg.valid_encoding?

      raise UsageError, "Argument #{arg.inspect} is not valid #{arg.encoding.name} text. " \
                        'cov-loupe works with UTF-8 paths and options.'
    end

    private def extract_env_opts
      require_relative 'cov_loupe/option_parsers/env_options_parser'
      OptionParsers::EnvOptionsParser.new.parse_env_opts
    end

    # Returns COV_LOUPE_OPTS split into arguments, and the command line, both retagged as
    # UTF-8, after checking that every argument is valid text. COV_LOUPE_OPTS text that is
    # not valid in its encoding (such as non-UTF-8 bytes under a UTF-8 locale) fails to
    # split; under LANG=C it arrives as binary, which is always valid. So an invalid argument
    # here is from the command line, and its message names it.
    private def global_argv(argv)
      env_argv = extract_env_opts.map { |arg| utf8_arg(arg) }
      cli_argv = argv.map { |arg| utf8_arg(arg) }
      (env_argv + cli_argv).each { |arg| validate_arg_encoding(arg) }
      [env_argv, cli_argv]
    rescue ConfigurationError, UsageError => e
      # An unsplittable COV_LOUPE_OPTS gets no note: its message already names COV_LOUPE_OPTS.
      report_global_usage_error(e, from_env: false)
    end

    # Parses COV_LOUPE_OPTS, then the command line, into one config, so an error is known to
    # be in one or the other; the error message itself cannot say which. A word in
    # COV_LOUPE_OPTS that is not an option (a subcommand), or a '--', ends the options, as it
    # would in a single parse of both, so the command line is then not parsed for options.
    # Returns the validated config, the arguments after the options (the subcommand and its
    # arguments), and the options typed on the command line, for usage hints. When
    # COV_LOUPE_OPTS ended the options, the whole command line is in the arguments, and no
    # options are returned for the hints.
    private def parse_global_options(env_argv, cli_argv)
      parser = ConfigParser.new
      rest = parse_options_from(parser, env_argv, from_env: true)
      # The settings from COV_LOUPE_OPTS alone. A shallow copy is enough: the option
      # handlers replace values rather than change them.
      env_config = parser.config.dup
      if parser.options_ended?
        rest += cli_argv
        cli_options = []
      else
        rest = parse_options_from(parser, cli_argv, from_env: false)
        # Parsing stops at the first non-option (order!), so the options, with any '--' that
        # ended them, are a prefix.
        cli_options = cli_argv.first(cli_argv.size - rest.size)
      end

      begin
        parser.config.validate!
      rescue ConfigurationError => e
        # validate! sees each option's last value, so the error is in COV_LOUPE_OPTS when its
        # settings alone are invalid: the command line did not override the bad value. This
        # holds while each validation rule checks a single setting. With no COV_LOUPE_OPTS,
        # an invalid default is not its fault.
        report_global_usage_error(e, from_env: env_argv.any? && !valid_config?(env_config))
      end
      [parser.config, rest, cli_options]
    end

    # Returns the arguments left after the options.
    private def parse_options_from(parser, args, from_env:)
      rest = args.dup
      parser.parse_options(rest)
      rest
    rescue OptionParser::ParseError, ConfigurationError, UsageError => e
      report_global_usage_error(e, argv: args, from_env: from_env)
    end

    private def valid_config?(config)
      config.validate!
      true
    rescue ConfigurationError
      false
    end

    # Reports a usage error in the global options and exits with the usage status. When the
    # error is in COV_LOUPE_OPTS, a line saying so comes before the --help line. argv, used
    # only for an OptionParser error, is the arguments whose parse failed.
    private def report_global_usage_error(error, from_env:, argv: [])
      # Loaded only on this error path to keep normal startup light.
      require_relative 'cov_loupe/option_parsers/error_helper'
      note = "The error is in #{env_opts_description}, which is read before the command line." if from_env
      hint = [note, OptionParsers::ErrorHelper::USAGE_HINT].compact.join("\n")
      if error.is_a?(OptionParser::ParseError)
        require_relative 'cov_loupe/subcommands'
        OptionParsers::ErrorHelper.new(SUBCOMMANDS)
          .handle_option_parser_error(error, argv: argv, usage_hint: hint)
      else
        warn "Error: #{error.message}"
        warn hint
        raise CliExit, ExitCodes::USAGE
      end
    end

    # Retagged as UTF-8 like the arguments, so non-ASCII text is shown rather than escaped.
    private def env_opts_description
      require_relative 'cov_loupe/option_parsers/env_options_parser'
      env_var = OptionParsers::EnvOptionsParser::ENV_VAR
      "#{env_var} (#{utf8_arg(ENV[env_var]).inspect})"
    end
  end
end
