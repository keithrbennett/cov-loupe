# frozen_string_literal: true

require 'json'
require_relative 'config/app_config'
require_relative 'config/option_parser_builder'
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
  # Dispatches to subcommand classes via CommandFactory, with the global options (coverage
  # file path, format, sort order, etc.) already parsed by CovLoupe.run. When no subcommand
  # is given, the default report (equivalent to `list`) is shown. Global options placed
  # after the subcommand trigger a helpful error message.
  #
  # @api private
  class CoverageCLI
    HORIZONTAL_RULE = '-' * 79

    # Optional single-character abbreviations for subcommands.
    SUBCOMMAND_ABBREVIATIONS = {
      'd' => 'detailed',
      'l' => 'list',
      'r' => 'raw',
      's' => 'summary',
      't' => 'totals',
      'u' => 'uncovered',
      'v' => 'validate',
    }.freeze

    attr_reader :config

    # Initialize CLI for pure CLI usage only.
    # Always runs as CLI, no mode detection needed.
    def initialize(error_handler: nil)
      @config = AppConfig.new
      @custom_error_handler = error_handler # Store custom handler if provided
      @global_args = []
      @error_handler = nil # Created on first use, from config's error mode
    end

    # Runs a subcommand, or the default report, with options already parsed into config.
    # @param args [Array<String>] the arguments after the global options: the subcommand
    #   and its arguments
    # @param config [AppConfig] the parsed global options; the caller must have validated them
    # @param global_args [Array<String>] the global options as typed on the command line,
    #   for usage hints
    def run(args, config:, global_args:)
      @config = config
      @global_args = global_args
      # Resolve single-character abbreviations (e.g., 's' -> 'summary')
      cmd = SUBCOMMAND_ABBREVIATIONS[args.first] || args.first

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
      params[:tracked_globs] = config.tracked_globs if config.tracked_globs&.any?
      params[:error_mode] = config.error_mode if config.error_mode
      CovLoupe.logger.info("CLI parameters: #{params.inspect}")
    end

    def show_default_report(sort_order: :descending, output: $stdout)
      model = CoverageModel.new(**config.model_options)
      presenter = Presenters::ProjectCoveragePresenter.new(
        model:          model,
        sort_order:     sort_order,
        raise_on_stale: config.raise_on_stale,
        tracked_globs:  config.tracked_globs
      )

      if config.format == :table
        file_summaries = presenter.relative_files
        output.puts model.format_table(
          file_summaries,
          sort_order:     sort_order,
          raise_on_stale: config.raise_on_stale,
          tracked_globs:  nil,
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
        # Check if user mistakenly placed global options after the subcommand
        check_for_misplaced_global_options(cmd, args)

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

    private def check_for_misplaced_global_options(cmd, args)
      switches = global_option_switches
      misplaced = []
      remaining = []
      tokens = args.dup
      while (arg = tokens.shift)
        # Extract base option (e.g., --format from --format=json)
        switch = switches[arg.split('=', 2).first]
        if switch.nil?
          remaining << arg
        elsif arg.include?('=') || !switch.is_a?(OptionParser::Switch::RequiredArgument)
          misplaced << arg
        elsif tokens.empty? || switches.key?(tokens.first.split('=', 2).first)
          # Without a value, show a placeholder (e.g. <MODE>) for the user to fill in.
          misplaced.push(arg, Placeholder.new(switch.arg.strip))
        else
          misplaced.push(arg, tokens.shift)
        end
      end
      return if misplaced.empty?

      raise UsageError, "Global option(s) must come BEFORE the subcommand.\n" \
        "You used: #{shell_command(*@global_args, cmd, *args)}\n" \
        "Correct: #{shell_command(*with_options_before_subcommand(misplaced), cmd, *remaining)}"
    end

    # A value the user must supply, shown unquoted as <NAME> in usage hints.
    Placeholder = Data.define(:name) do
      def to_s = "<#{name}>"
    end
    private_constant :Placeholder

    # Inserts options among those given before the subcommand. They must precede a `--`,
    # since option parsing stops there.
    private def with_options_before_subcommand(options)
      return [*@global_args, *options] unless ends_with_terminator?(@global_args)

      [*@global_args[0...-1], *options, '--']
    end

    # True if args end with a `--` terminator, as opposed to a `--` that is an option's value.
    private def ends_with_terminator?(args)
      switches = global_option_switches
      index = 0
      while index < args.size
        return index == args.size - 1 if args[index] == '--'

        index += 1 if switches[args[index]].is_a?(OptionParser::Switch::RequiredArgument)
        index += 1
      end
      false
    end

    # Global option switches keyed by each of their flags (e.g. '-f' and '--format').
    # Help is left out: after a subcommand it is reported as an unexpected argument.
    private def global_option_switches
      OptionParserBuilder.new(config).build_option_parser.top.list
        .grep(OptionParser::Switch)
        .reject { |switch| switch.long.include?('--help') }
        .each_with_object({}) do |switch, by_flag|
          (switch.short + switch.long).flat_map { |flag| flag_spellings(flag) }
            .each { |flag| by_flag[flag] = switch }
        end
    end

    # A negatable switch is listed as --[no-]name; it can be typed as --name or --no-name.
    private def flag_spellings(flag)
      return [flag] unless flag.include?('[no-]')

      [flag.sub('[no-]', ''), flag.sub('[no-]', 'no-')]
    end

    # Formats a command line for copying into a shell, quoting arguments that need it.
    private def shell_command(*args)
      ['cov-loupe', *args].map do |arg|
        next arg.to_s if arg.is_a?(Placeholder)

        # Block form: in a replacement string, \' would mean the text after the match.
        arg.match?(%r{\A[\w@%+=:,./-]+\z}) ? arg : "'#{arg.gsub("'") { "'\\''" }}'"
      end.join(' ')
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
