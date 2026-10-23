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
#   3. ModelDataCache stores the resulting ModelData (coverage_map + timestamp)
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
    # 1. Thread-local: Use `Thread.current[:cov_loupe_context]` if set.
    # 2. Global default: Fall back to `@internal_default_context`.
    #
    # This design supports both simple CLI usage (one global context) and multi-threaded
    # library usage (per-thread contexts).
    #
    # Thread Safety:
    # - `mutex` protects all reads/writes to `@internal_default_context`.
    # - `default_log_file=` atomically updates the global default. Threads using the
    #   default (nil thread-local context) will immediately see the new value.
    # - `active_log_file=` creates or updates a *thread-local* context, isolating
    #   changes to the current thread.
    #
    # This separation ensures that changing the global default is safe and predictable,
    # while allowing threads to diverge when necessary without race conditions.

    THREAD_CONTEXT_KEY = :cov_loupe_context
    private_constant :THREAD_CONTEXT_KEY

    # Primary entry point. Parses argv to determine mode (CLI or MCP server),
    # then dispatches accordingly. Environment options from COV_LOUPE_OPTS are
    # prepended before parsing so CLI arguments always take precedence.
    #
    # @api public
    def run(argv)
      # Parse config to determine mode
      require_relative 'cov_loupe/config/config_parser'

      begin
        # Prepend environment options once at entry point
        env_argv = extract_env_opts
        full_argv = (env_argv + argv).map { |arg| utf8_arg(arg) }
        config = ConfigParser.parse(full_argv.dup)
      rescue OptionParser::ParseError => e
        # Loaded only on this error path to keep normal startup light.
        require_relative 'cov_loupe/subcommands'
        require_relative 'cov_loupe/option_parsers/error_helper'
        OptionParsers::ErrorHelper.new(SUBCOMMANDS)
          .handle_option_parser_error(e, argv: full_argv)
      rescue ConfigurationError, UsageError => e
        warn "Error: #{e.message}"
        warn "Run 'cov-loupe --help' for usage information."
        exit ExitCodes::USAGE
      end

      if config.mode == :cli
        # CLI mode: load CLI components only
        require_relative 'cov_loupe/loaders/all_cli'
        CoverageCLI.new.run(full_argv, env_arg_count: env_argv.size)
      else
        # MCP server mode: load MCP server components only
        require_relative 'cov_loupe/loaders/all_mcp'

        handler = ErrorHandlerFactory.for_mcp_server(error_mode: config.error_mode)
        context = create_context(error_handler: handler, log_target: config.log_file,
          mode: :mcp, app_config: config)
        with_context(context) { MCPServer.new(context: context).run }
      end
    end

    # Temporarily sets a thread-local context for the duration of the block,
    # restoring the previous context afterward. Used to scope logging and
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

    private def extract_env_opts
      require_relative 'cov_loupe/option_parsers/env_options_parser'
      OptionParsers::EnvOptionsParser.new.parse_env_opts
    end
  end
end
