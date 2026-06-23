# frozen_string_literal: true

require 'logger'
require 'time'
require_relative '../errors/errors'

module CovLoupe
  # Custom logger that gracefully handles logging failures.
  #
  # Log targets:
  #   - File path (default: ./cov_loupe.log)
  #   - 'stderr' for stream output
  #   - ':off' to disable logging entirely
  #   - nil for default file logging
  #
  # 'stdout' is never a valid target because it would corrupt command output.
  #
  # If the primary log target fails (e.g., permission denied), the logger falls back
  # to writing to COV-LOUPE-LOG-ERROR.log and emits a one-time stderr warning in CLI mode.
  # The safe_log method never raises, making it safe for use in rescue blocks.
  class Logger
    DEFAULT_LOG_FILESPEC = './cov_loupe.log'
    FALLBACK_LOG_FILE = 'COV-LOUPE-LOG-ERROR.log'

    attr_reader :target

    def initialize(target:, mode: :library)
      if target.to_s.strip.downcase == 'stdout'
        raise ConfigurationError,
          'Logging to stdout is not permitted because it corrupts command output. ' \
          "Use 'stderr', a file path, or ':off' to disable logging."
      end

      @mode = mode
      @target = target
      @init_error = nil
      @stderr_warning_emitted = false
      @disabled = logging_disabled?(target)

      return if @disabled

      begin
        @logger = build_logger(target)
      rescue => e
        @init_error = e
      end
    end

    def info(msg)
      return if @disabled

      log_with_level(:info, msg)
    end

    def warn(msg)
      return if @disabled

      log_with_level(:warn, msg)
    end

    def error(msg)
      return if @disabled

      log_with_level(:error, msg)
    end

    # Safe logging that never raises - use when logging should not interrupt execution.
    def safe_log(msg)
      return if @disabled

      info(msg)
    rescue
      # Silently ignore all logging failures
    end

    private def logging_disabled?(target)
      return false if target.nil?

      target.to_s.strip.downcase == ':off'
    end

    private def log_with_level(level, msg)
      if @init_error
        handle_logging_error(@init_error, msg)
      else
        @logger.send(level, msg)
      end
    rescue => e
      handle_logging_error(e, msg)
    end

    private def build_logger(target)
      io_or_path = if target == 'stderr'
        $stderr
      else
        path = target || DEFAULT_LOG_FILESPEC
        File.expand_path(path)
      end

      ::Logger.new(io_or_path).tap do |l|
        l.formatter = ->(severity, datetime, _progname, msg) { "[#{datetime.iso8601}] #{severity}: #{msg}\n" }
      end
    end

    private def handle_logging_error(error, original_msg)
      write_fallback_file(error, original_msg)
      warn_stderr_once if @mode == :cli
    rescue
      # Silently ignore all fallback failures
    end

    private def write_fallback_file(error, original_msg)
      File.open(FALLBACK_LOG_FILE, 'a') do |f|
        timestamp = Time.now.iso8601
        f.puts "[#{timestamp}] MODE:#{@mode} ERROR:#{error.message} MSG:#{original_msg}"
      end
    rescue
      # Best effort - ignore write failures
    end

    private def warn_stderr_once
      return if @stderr_warning_emitted

      @stderr_warning_emitted = true
      $stderr.puts "Warning: Logging failed. See #{FALLBACK_LOG_FILE} for details."
    end
  end
end
