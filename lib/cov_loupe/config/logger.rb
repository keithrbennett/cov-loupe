# frozen_string_literal: true

require 'logger'
require 'time'
require_relative '../errors/errors'

module CovLoupe
  # Logger that validates its target at startup and creates the underlying logger
  # only when the first message is written.
  #
  # Log targets:
  #   - File path (default: ./cov_loupe.log)
  #   - 'stderr' for stream output
  #   - ':off' to disable logging entirely
  #   - nil for default file logging
  #
  # 'stdout' is never a valid target because it would corrupt command output.
  #
  # A failed startup probe is reported according to the active mode: library mode
  # raises, MCP mode reports an error result for tool calls, and CLI mode warns on
  # stderr. Later write failures fall back to COV-LOUPE-LOG-ERROR.log and emit a
  # one-time stderr warning in CLI mode. The safe_log method suppresses logging
  # failures, making it safe for use in rescue blocks.
  class Logger
    DEFAULT_LOG_FILESPEC = './cov_loupe.log'
    FALLBACK_LOG_FILE = 'COV-LOUPE-LOG-ERROR.log'

    attr_reader :target

    def initialize(target:, mode: :library)
      if normalized_target(target) == 'stdout'
        raise ConfigurationError,
          'Logging to stdout is not permitted because it corrupts command output. ' \
          "Use 'stderr', a file path, or ':off' to disable logging."
      end

      @mode = mode
      @target = target
      @init_error = nil
      @stderr_warning_emitted = false
      @fallback_warning_emitted = false
      @disabled = logging_disabled?(target)
      @logger = nil

      @init_error = logging_error_for(probe_logger_target(target)) unless @disabled
      report_initialization_error if @init_error
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

    def raise_if_initialization_failed!
      raise @init_error if @init_error
    end

    private def normalized_target(target)
      target.to_s.strip.downcase
    end

    private def logging_disabled?(target)
      return false if target.nil?

      normalized_target(target) == ':off'
    end

    private def stderr_target?(target)
      normalized_target(target) == 'stderr'
    end

    private def report_initialization_error
      if @mode == :library
        raise @init_error
      else
        warn_stderr_once(@init_error)
      end
    end

    private def probe_logger_target(target)
      return if stderr_target?(target)

      path = File.expand_path(target || DEFAULT_LOG_FILESPEC)
      if File.exist?(path)
        verify_append_access(path)
        return
      end

      created = false
      # Open write-only and create only if missing. EXCL makes creation race-safe;
      # EEXIST is handled by opening the file in append mode below.
      open_flags = File::WRONLY | File::CREAT | File::EXCL
      begin
        File.open(path, open_flags, 0o644) do
          created = true
        end
      rescue Errno::EEXIST
        verify_append_access(path)
      ensure
        File.delete(path) if created && File.exist?(path)
      end
      nil
    rescue => e
      e
    end

    private def verify_append_access(path)
      # Opening in append mode is the access check; no write is needed.
      File.open(path, 'a') {} # rubocop:disable Style/FileTouch
    end

    private def log_with_level(level, msg)
      unless @logger || @init_error
        begin
          @logger = build_logger(@target)
        rescue => e
          @init_error = logging_error_for(e)
        end
      end

      if @init_error
        handle_logging_error(@init_error, msg)
      else
        @logger.send(level, msg)
      end
    rescue LoggingError
      raise
    rescue => e
      handle_logging_error(e, msg)
    end

    private def build_logger(target)
      io_or_path = if stderr_target?(target)
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
      logging_error = logging_error_for(error)
      write_fallback_file(error, original_msg)
      raise logging_error if %i[library mcp].include?(@mode)

      warn_stderr_once(logging_error, fallback: true) if @mode == :cli
    rescue LoggingError
      raise
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

    private def warn_stderr_once(error, fallback: false)
      if fallback
        return if @fallback_warning_emitted

        @fallback_warning_emitted = true
      else
        return if @stderr_warning_emitted

        @stderr_warning_emitted = true
      end
      message = "Warning: #{error.user_friendly_message}"
      message += " See #{FALLBACK_LOG_FILE} for details." if fallback
      $stderr.puts message
    end

    private def logging_error_for(error)
      return error if error.nil? || error.is_a?(LoggingError)

      LoggingError.new(@target, error.message, error)
    end
  end
end
