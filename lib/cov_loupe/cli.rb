# frozen_string_literal: true

require 'json'
require_relative 'config/app_config'
require_relative 'config/option_parser_builder'
require_relative 'commands/command_factory'
require_relative 'option_parsers/error_helper'
require_relative 'option_parsers/env_options_parser'
require_relative 'presenters/project_coverage_presenter'
require_relative 'output_chars'
require_relative 'resources'

module CovLoupe
  # Command-line interface for cov-loupe.
  #
  # Parses global options (resultset path, format, sort order, etc.) and dispatches
  # to subcommand classes via CommandFactory. When no subcommand is given, the default
  # report (equivalent to `list`) is shown.
  #
  # Option parsing uses order! so that global options before the subcommand are consumed
  # and the subcommand name + its arguments remain in argv. Global options placed after
  # the subcommand trigger a helpful error message.
  class CoverageCLI
    HORIZONTAL_RULE = '-' * 79

    # Valid CLI subcommands.
    SUBCOMMANDS = %w[list summary raw uncovered detailed totals validate].freeze

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
      @custom_error_handler = error_handler # Store custom handler if provided
      @error_handler = nil # Will be created after parsing options
    end

    def run(argv)
      context = nil
      # argv should already include environment options (merged by caller)
      # Pre-scan for error-mode to ensure early errors are logged with correct verbosity
      pre_scan_error_mode(argv)
      parse_options!(argv)

      context = CovLoupe.create_context(
        error_handler: error_handler, # construct after options to respect --error-mode
        log_target:    config.log_file.nil? ? CovLoupe.context.log_target : config.log_file,
        mode:          :cli
      )

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
      with_context_if_available(context) { handle_user_facing_error(e) }
    end

    private def log_cli_params
      # Log CLI parameters for transparency
      if CovLoupe.logger
        params = { mode: :cli, subcommand: @cmd || 'default' }
        params[:root] = config.root if config.root
        params[:resultset] = config.resultset if config.resultset
        params[:format] = config.format if config.format
        params[:sort_order] = config.sort_order if config.sort_order
        params[:raise_on_stale] = config.raise_on_stale if config.raise_on_stale
        params[:tracked_globs] = config.tracked_globs if config.tracked_globs&.any?
        params[:error_mode] = config.error_mode if config.error_mode
        CovLoupe.logger.info("CLI parameters: #{params.inspect}")
      end
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
        show_exclusions_summary(presenter, $stderr)
        warn_missing_timestamps(presenter, $stderr)
      else
        require_relative 'formatters/formatters'
        output.puts Formatters.format(presenter.relativized_payload, config.format,
          output_chars: config.output_chars)
      end

      warn_skipped_rows(presenter)
      warn_missing_timestamps(presenter)
    end

    private def parse_options!(argv)
      require 'optparse'
      parser = OptionParserBuilder.new(config).build_option_parser

      # order! parses global options (updating config) and removes them from argv.
      # It stops cleanly at the first subcommand (e.g., 'list', 'summary') or unknown option.
      # If it stops at an unknown option, it raises OptionParser::InvalidOption.
      parser.order!(argv)

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
      error_handler.handle_error(e, context: "subcommand '#{cmd}'")
    end

    private def handle_option_parser_error(error, argv: [])
      @error_helper ||= OptionParsers::ErrorHelper.new(SUBCOMMANDS)
      @error_helper.handle_option_parser_error(error, argv: argv, output_chars: config.output_chars)
    end

    private def check_for_misplaced_global_options(cmd, args)
      # Global options that users commonly place after subcommands by mistake
      global_options = %w[-r --resultset -R --root -f --format -o --sort-order -s --source
        -c --context-lines -S --raise-on-stale -g --tracked-globs
        -l --log-file --error-mode --color -m --mode -v --version
        -p --path-for
        -O --output-chars]

      misplaced = args.select do |arg|
        # Extract base option (e.g., --format from --format=json)
        base = arg.split('=', 2).first
        global_options.include?(base)
      end
      return if misplaced.empty?

      option_list = misplaced.join(', ')
      raise UsageError, "Global option(s) must come BEFORE the subcommand.\n" \
        "You used: #{cmd} #{option_list}\n" \
        "Correct: #{option_list} #{cmd}\n\n" \
        "Example: cov-loupe --format json #{cmd}"
    end

    private def handle_user_facing_error(error)
      error_handler.handle_error(error, context: 'CLI', reraise: false)
      # Convert error message to ASCII if in ascii mode
      message = OutputChars.convert(error.user_friendly_message, config.output_chars)
      warn message
      warn error.backtrace.first(5).join("\n") if config.error_mode == :debug && error.backtrace
      exit 1
    end

    private def warn_skipped_rows(presenter)
      skipped = presenter.relative_skipped_files
      return if skipped.nil? || skipped.empty?

      count = skipped.length
      warn ''
      warn "WARNING: #{count} coverage row#{count == 1 ? '' : 's'} skipped due to errors:"
      skipped.each do |row|
        # Paths are already relativized by presenter
        file_path = OutputChars.convert(row['file'], config.output_chars)
        error_msg = OutputChars.convert(row['error'], config.output_chars)
        warn "  - #{file_path}: #{error_msg}"
      end
      warn 'Run again with --raise-on-stale to exit when rows are skipped.'
    end

    private def output_file_list(output, files, header)
      return if files.empty?

      output.puts "\n#{header} (#{files.length}):"
      files.each do |file|
        output.puts('  - ' + OutputChars.convert(file, config.output_chars))
      end
    end

    private def warn_missing_timestamps(presenter, output = $stderr)
      return unless presenter.timestamp_status == 'missing'

      output.puts <<~WARNING

        WARNING: Coverage timestamps are missing. Time-based staleness checks were skipped.
        Files may appear "ok" even if source code is newer than the coverage data.
        Check your coverage tool configuration to ensure timestamps are recorded.
      WARNING
    end

    private def show_exclusions_summary(presenter, output)
      missing = presenter.relative_missing_tracked_files
      newer = presenter.relative_newer_files
      deleted = presenter.relative_deleted_files
      length_mismatch = presenter.relative_length_mismatch_files
      unreadable = presenter.relative_unreadable_files
      skipped = presenter.relative_skipped_files

      # Only show if there are any exclusions
      return if missing.empty? && newer.empty? && deleted.empty? &&
        length_mismatch.empty? && unreadable.empty? && skipped.empty?

      output.puts "\nFiles excluded from coverage:"

      output_file_list(output, missing, 'Missing tracked files')
      output_file_list(output, newer, 'Files newer than coverage')
      output_file_list(output, deleted, 'Deleted files with coverage')
      output_file_list(output, length_mismatch, 'Line count mismatches')
      output_file_list(output, unreadable, 'Unreadable files')

      unless skipped.empty?
        output.puts "\nFiles skipped due to errors (#{skipped.length}):"
        skipped.each do |row|
          file_path = OutputChars.convert(row['file'], config.output_chars)
          error_msg = OutputChars.convert(row['error'], config.output_chars)
          output.puts "  - #{file_path}: #{error_msg}"
        end
      end

      output.puts "\nRun with --raise-on-stale to exit when files are excluded."
    end
  end
end
