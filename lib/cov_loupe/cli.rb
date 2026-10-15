# frozen_string_literal: true

require 'json'
require_relative 'config/app_config'
require_relative 'config/option_parser_builder'
require_relative 'commands/command_factory'
require_relative 'option_parsers/error_helper'
require_relative 'option_parsers/env_options_parser'
require_relative 'presenters/project_coverage_presenter'
require_relative 'exit_codes'
require_relative 'subcommands'
require_relative 'output_chars'
require_relative 'formatters/coverage_warnings'
require_relative 'payload_schema'
require_relative 'resources'

module CovLoupe
  # Command-line interface for cov-loupe.
  #
  # Parses global options (coverage file path, format, sort order, etc.) and dispatches
  # to subcommand classes via CommandFactory. When no subcommand is given, the default
  # report (equivalent to `list`) is shown.
  #
  # Option parsing uses order! so that global options before the subcommand are consumed
  # and the subcommand name + its arguments remain in argv. Global options placed after
  # the subcommand trigger a helpful error message.
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
      @cmd = nil
      @cmd_args = []
      @global_args = [] # Arguments given before the subcommand
      @custom_error_handler = error_handler # Store custom handler if provided
      @error_handler = nil # Will be created after parsing options
    end

    # @param env_arg_count [Integer] how many leading argv entries came from COV_LOUPE_OPTS
    #   rather than the user's command line (used to keep them out of usage hints)
    def run(argv, env_arg_count: 0)
      context = nil
      @env_arg_count = env_arg_count
      # argv should already include environment options (merged by caller)
      # Pre-scan for error-mode to ensure early errors are logged with correct verbosity
      pre_scan_error_mode(argv)
      parse_options!(argv)

      context = build_context

      CovLoupe.with_context(context) do
        log_cli_params
        if @cmd
          run_subcommand(@cmd, @cmd_args)
        else
          show_default_report(sort_order: config.sort_order)
        end
      end
    rescue OptionParser::ParseError => e
      # Handle any option parsing errors (invalid option/argument) without relying on
      # @error_handler, which is not guaranteed to be initialized yet.
      with_context_if_available(context) { handle_option_parser_error(e, argv: argv) }
    rescue CovLoupe::Error => e
      with_context_if_available(context || early_error_context) { handle_user_facing_error(e) }
    end

    private def build_context
      CovLoupe.create_context(
        error_handler: error_handler, # construct after options to respect --error-mode
        log_target:    config.log_file.nil? ? CovLoupe.context.log_target : config.log_file,
        mode:          :cli
      )
    end

    # Context for usage errors raised after option parsing (e.g. an unknown subcommand), so
    # they still reach --log-file. Returns nil for errors raised while parsing options, as the
    # options may be incomplete, or if the context cannot be created (e.g. for a `stdout`
    # log target).
    private def early_error_context
      return unless @options_parsed

      build_context
    rescue CovLoupe::Error
      nil
    end

    # Records CLI parameters in a log file. Skipped for stderr so routine runs stay quiet.
    private def log_cli_params
      return unless CovLoupe.logger.file_target?

      params = { mode: :cli, subcommand: @cmd || 'default' }
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
        warn_report_text(Formatters::CoverageWarnings.exclusions_summary(presenter, config.output_chars))
      else
        require_relative 'formatters/formatters'
        output.puts Formatters.format(PayloadSchema.add(presenter.relativized_payload), config.format,
          output_chars: config.output_chars)
        warn_report_text(Formatters::CoverageWarnings.skipped_rows_warning(presenter, config.output_chars))
      end

      warn_report_text(Formatters::CoverageWarnings.timestamp_warning(presenter))
    end

    private def warn_report_text(text)
      warn text unless text.empty?
    end

    private def parse_options!(argv)
      require 'optparse'
      parser = OptionParserBuilder.new(config).build_option_parser

      # order! parses global options (updating config) and removes them from argv.
      # It stops cleanly at the first subcommand (e.g., 'list', 'summary') or unknown option.
      # If it stops at an unknown option, it raises OptionParser::InvalidOption.
      original_argv = argv.dup
      parser.order!(argv)
      @options_parsed = true
      @global_args = original_argv.first(original_argv.size - argv.size).drop(@env_arg_count.to_i)

      # The first remaining argument is the subcommand
      @cmd = argv.shift

      # Resolve single-character abbreviations (e.g., 's' -> 'summary')
      @cmd = SUBCOMMAND_ABBREVIATIONS[@cmd] || @cmd

      # Verify it's a valid subcommand if present
      if @cmd && !SUBCOMMANDS.include?(@cmd)
        raise UsageError, "Unknown subcommand: '#{@cmd}'. Valid subcommands: #{SUBCOMMANDS.join(', ')}"
      end

      # Any remaining arguments belong to the subcommand
      @cmd_args = argv

      config.validate!
    end

    private def error_handler
      @error_handler ||= @custom_error_handler ||
        ErrorHandlerFactory.for_cli(error_mode: config.error_mode)
    end

    private def pre_scan_error_mode(argv)
      env_parser = OptionParsers::EnvOptionsParser.new
      config.error_mode = env_parser.pre_scan_error_mode(argv) || :log
    end

    private def with_context_if_available(ctx, &block)
      if ctx
        CovLoupe.with_context(ctx, &block)
      else
        block.call
      end
    end

    private def run_subcommand(cmd, args)
      # Check if user mistakenly placed global options after the subcommand
      check_for_misplaced_global_options(cmd, args)

      command = Commands::CommandFactory.create(cmd, self)
      command.execute(args)
    rescue CovLoupe::Error => e
      handle_user_facing_error(e)
    rescue => e
      # Log the original error (not the conversion) so its class reaches the log.
      # Custom error handlers need not implement conversion.
      converter = error_handler.respond_to?(:convert_standard_error) ? error_handler : ErrorHandler.new
      handle_user_facing_error(converter.convert_standard_error(e),
        log_error: e, log_context: "subcommand '#{cmd}'")
    end

    private def handle_option_parser_error(error, argv: [])
      @error_helper ||= OptionParsers::ErrorHelper.new(SUBCOMMANDS)
      @error_helper.handle_option_parser_error(error, argv: argv, output_chars: config.output_chars)
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
      # Convert error message to ASCII if in ascii mode
      message = OutputChars.convert(error.user_friendly_message, config.output_chars)
      warn message
      if config.error_mode == :debug && (backtrace = error.diagnostic_backtrace)
        # A log file gets the full trace; with a stderr target there is no log entry, so show it all.
        backtrace = backtrace.first(5) unless CovLoupe.logger.stderr?
        warn OutputChars.convert(backtrace.join("\n"), config.output_chars)
      end
      exit(exit_code_for(error))
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
