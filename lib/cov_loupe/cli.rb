# frozen_string_literal: true

require 'json'
require_relative 'config/app_config'
require_relative 'commands/command_factory'
require_relative 'presenters/project_coverage_presenter'
require_relative 'exit_codes'
require_relative 'subcommands'
require_relative 'formatters/coverage_warnings'
require_relative 'payload_schema'
require_relative 'resources'

module CovLoupe
  # Command-line interface for cov-loupe.
  #
  # Dispatches to subcommand classes via CommandFactory, with the options (coverage file
  # path, format, sort order, etc.), before and after the subcommand, already parsed by
  # CovLoupe.run. When no subcommand is given, the default report (equivalent to `list`) is
  # shown.
  #
  # @api private
  class CoverageCLI
    HORIZONTAL_RULE = '-' * 79

    # inline_code is validate's -i code, or nil.
    attr_reader :config, :inline_code

    # Initialize CLI for pure CLI usage only.
    # Always runs as CLI, no mode detection needed.
    def initialize(error_handler: nil)
      @config = AppConfig.new
      @custom_error_handler = error_handler # Store custom handler if provided
      @inline_code = nil
      @error_handler = nil # Created on first use, from config's error mode
    end

    # Runs a subcommand, or the default report, with options already parsed into config.
    # @param args [Array<String>] the subcommand and its positional arguments (for a known
    #   subcommand, CovLoupe.run has removed the options after it)
    # @param config [AppConfig] the parsed global options; the caller must have validated them
    # @param inline_code [String, nil] validate's -i code, parsed with the options after the
    #   subcommand
    def run(args, config:, inline_code: nil)
      @config = config
      @inline_code = inline_code
      # Resolve single-character abbreviations (e.g., 's' -> 'summary')
      cmd = CovLoupe::SUBCOMMAND_ABBREVIATIONS[args.first] || args.first

      CovLoupe.with_context(build_context) do
        # Raised, not just built, so that --error-mode debug has a backtrace to show.
        if cmd && !SUBCOMMANDS.include?(cmd)
          with_user_facing_errors('CLI') do
            raise UsageError, "Unknown subcommand: '#{cmd}'. Valid subcommands: #{SUBCOMMANDS.join(', ')}"
          end
        end
        log_cli_params(cmd)
        cmd ? run_subcommand(cmd, args.drop(1)) : run_default_report
      end
    end

    private def build_context
      CovLoupe.create_context(
        error_handler: error_handler, # construct after options to respect --error-mode
        log_target:    config.log_file.nil? ? CovLoupe.context.log_target : config.log_file,
        mode:          :cli
      )
    end

    # Records CLI parameters in a log file. Skipped for stderr so routine runs stay quiet.
    private def log_cli_params(cmd)
      return unless CovLoupe.logger.file_target?

      params = { mode: :cli, subcommand: cmd || 'default' }
      params[:root] = config.root if config.root
      params[:coverage_file] = config.coverage_file if config.coverage_file
      params[:format] = config.format if config.format
      params[:sort_order] = config.sort_order if config.sort_order
      params[:raise_on_stale] = config.raise_on_stale if config.raise_on_stale
      params[:file_globs] = config.file_globs if config.file_globs&.any?
      params[:error_mode] = config.error_mode if config.error_mode
      CovLoupe.logger.info("CLI parameters: #{params.inspect}")
    end

    def show_default_report(sort_order: :descending, output: $stdout)
      model = CoverageModel.new(**config.model_options)
      presenter = Presenters::ProjectCoveragePresenter.new(
        model:          model,
        sort_order:     sort_order,
        raise_on_stale: config.raise_on_stale,
        file_globs:     config.file_globs
      )

      if config.format == :table
        file_summaries = presenter.relative_files
        output.puts model.format_table(
          file_summaries,
          sort_order:     sort_order,
          raise_on_stale: config.raise_on_stale,
          file_globs:     nil,
          output_chars:   config.output_chars
        )
        # The exclusions summary already lists skipped rows.
        warn_report_text(Formatters::CoverageWarnings.exclusions_summary(presenter))
      else
        require_relative 'formatters/formatters'
        output.puts Formatters.format(PayloadSchema.add(presenter.payload), config.format,
          output_chars: config.output_chars)
        warn_report_text(Formatters::CoverageWarnings.skipped_rows_warning(presenter))
      end

      warn_report_text(Formatters::CoverageWarnings.timestamp_warning(presenter))
      warn_report_text(Formatters::CoverageWarnings.root_warning(presenter))
    end

    private def warn_report_text(text)
      warn text unless text.empty?
    end

    private def error_handler
      @error_handler ||= @custom_error_handler ||
        ErrorHandlerFactory.for_cli(error_mode: config.error_mode)
    end

    private def run_subcommand(cmd, args)
      with_user_facing_errors("subcommand '#{cmd}'") do
        command = Commands::CommandFactory.create(cmd, self)
        command.execute(args)
      end
    end

    private def run_default_report
      with_user_facing_errors('default report') { show_default_report(sort_order: config.sort_order) }
    end

    private def with_user_facing_errors(log_context)
      yield
    rescue CovLoupe::Error => e
      handle_user_facing_error(e)
    rescue => e
      # Log the original error (not the conversion) so its class reaches the log.
      # Custom error handlers need not implement conversion.
      converter = error_handler.respond_to?(:convert_standard_error) ? error_handler : ErrorHandler.new
      handle_user_facing_error(converter.convert_standard_error(e), log_error: e, log_context: log_context)
    end

    private def handle_user_facing_error(error, log_error: error, log_context: 'CLI')
      log_user_facing_error(log_error, log_context)
      warn error.user_friendly_message
      if config.error_mode == :debug && (backtrace = error.diagnostic_backtrace)
        # A log file gets the full trace; with a stderr or off target nothing else records it,
        # so show it all.
        backtrace = backtrace.first(5) if CovLoupe.logger.file_target?
        warn backtrace.join("\n")
      end
      raise CliExit, exit_code_for(error)
    end

    # Errors are always printed to stderr for the user, so the built-in handler does not log them
    # there too. A custom handler always receives them; it may report them elsewhere.
    private def log_user_facing_error(error, context)
      return if @custom_error_handler.nil? && CovLoupe.logger.stderr?

      error_handler.handle_error(error, context: context, reraise: false)
    end

    # Usage and configuration mistakes are the user's to fix (2); everything else is a runtime
    # error (1), except predicate errors (4).
    private def exit_code_for(error)
      case error
      when PredicateError
        ExitCodes::PREDICATE_ERROR
      when UsageError, ConfigurationError
        ExitCodes::USAGE
      else
        ExitCodes::ERROR
      end
    end
  end
end
