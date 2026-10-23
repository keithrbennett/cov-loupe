# frozen_string_literal: true

require 'json'
require_relative 'errors'

module CovLoupe
  # Centralized error handling with configurable logging verbosity.
  #
  # Error modes:
  #   - :off   → suppress all logging
  #   - :log   → log error class, message, and context
  #   - :debug → same as :log plus full backtraces
  #
  # convert_standard_error maps Ruby's built-in exceptions to the CovLoupe error hierarchy,
  # using the `context` parameter to choose more specific messages (e.g., Errno::ENOENT
  # becomes CoverageFileNotFoundError in :coverage_loading context but FileNotFoundError otherwise).
  #
  # @api private
  class ErrorHandler
    attr_accessor :error_mode, :logger

    VALID_ERROR_MODES = %i[off log debug].freeze

    def initialize(error_mode: :log, logger: nil)
      unless VALID_ERROR_MODES.include?(error_mode)
        raise ArgumentError,
          "Invalid error_mode: #{error_mode.inspect}. Valid modes: #{VALID_ERROR_MODES.inspect}"
      end

      @error_mode = error_mode
      @logger = logger
    end

    def log_errors?
      error_mode != :off
    end

    def show_stack_traces?
      error_mode == :debug
    end

    # Handle an error with appropriate logging and re-raising behavior
    def handle_error(error, context: nil, reraise: true)
      log_error(error, context)
      if reraise
        raise error.is_a?(CovLoupe::Error) ? error : convert_standard_error(error, context: context)
      end
    end

    # Convert standard Ruby errors to user-friendly custom errors.
    # @param error [Exception] the error to convert
    # @param context [Symbol] :general (default) or :coverage_loading for context-specific messages
    def convert_standard_error(error, context: :general)
      case error
      when Errno::ENOENT
        convert_enoent(error, context)
      when Errno::EACCES
        convert_eacces(error, context)
      when Errno::EISDIR
        filename = extract_filename(error.message)
        NotAFileError.new("Expected file but found directory: #{filename}", error)
      when Errno::EMFILE, Errno::ENOSPC, IOError
        FileError.new(error.message, error)
      when Errno::EROFS
        FilePermissionError.new(error.message, error)
      when JSON::ParserError
        CoverageDataError.new("Invalid coverage data format: #{error.message}", error)
      when EncodingError
        convert_encoding_error(error, context)
      when RangeError
        CoverageDataError.new("Numeric overflow or range error: #{error.message}", error)
      when TypeError
        CoverageDataError.new("Invalid coverage data structure: #{error.message}", error)
      when ArgumentError
        convert_argument_error(error, context)
      when NoMethodError
        convert_no_method_error(error, context)
      else # including RuntimeError
        UnknownError.new(error.message, error)
      end
    end

    private def convert_enoent(error, context)
      if context == :coverage_loading
        CoverageFileNotFoundError.new('Coverage data not found', error)
      else
        filename = extract_filename(error.message)
        FileNotFoundError.new("File not found: #{filename}", error)
      end
    end

    private def convert_eacces(error, context)
      if context == :coverage_loading
        FilePermissionError.new("Permission denied reading coverage data: #{error.message}", error)
      else
        filename = extract_filename(error.message)
        FilePermissionError.new("Permission denied accessing file: #{filename}", error)
      end
    end

    # Outside coverage loading, an encoding error can come from output, a path argument or an
    # encoding setting, so the message names the likely settings rather than one cause.
    private def convert_encoding_error(error, context)
      if context == :coverage_loading
        CoverageDataError.new("Invalid encoding in coverage data: #{error.message}", error)
      else
        TextEncodingError.new("#{error.message.chomp('.')}. cov-loupe works with UTF-8 text; check that " \
          'the locale, any Ruby encoding options (such as -E or -U in RUBYOPT) and any paths ' \
          'you pass use UTF-8.', error)
      end
    end

    private def convert_argument_error(error, context)
      if context == :coverage_loading
        CoverageDataError.new("Invalid path in coverage data: #{error.message}", error)
      else
        # Deliberately raised user-input errors are UsageError/ConfigurationError already, so an
        # ArgumentError that reaches here is an unexpected (internal) failure.
        UnknownError.new(error.message, error)
      end
    end

    private def convert_no_method_error(error, context)
      if context == :coverage_loading
        CoverageDataError.new("Invalid coverage data structure: #{error.message}", error)
      else
        method_info = extract_method_info(error.message)
        CoverageDataError.new("Invalid coverage data structure - #{method_info}", error)
      end
    end


    private def log_error(error, context)
      return unless log_errors?

      message = build_log_message(error, context)
      active_logger = @logger || CovLoupe.logger
      active_logger.error(message)
    end

    # Build log message for error logging.
    # Messages are logged exactly as they are, in every output_chars mode: the mode only changes
    # how tables and markers are drawn, never data.
    private def build_log_message(error, context)
      context_suffix = context ? " in #{context}" : ''
      parts = ["Error#{context_suffix}: #{error.class}: #{error.message}"]

      if show_stack_traces?
        trace = error.is_a?(CovLoupe::Error) ? error.diagnostic_backtrace : error.backtrace
        parts << trace.join("\n") if trace
      end

      parts.join("\n")
    end

    private def extract_filename(message)
      # Extract filename from "No such file or directory @ rb_sysopen - filename"
      match = message.match(/@ \w+ - (.+)$/)
      match ? match[1] : 'unknown file'
    end

    private def extract_method_info(message)
      # Ruby < 3.4 quotes the method name as `name'; Ruby >= 3.4 uses 'name'.
      match = message.match(/undefined method [`'](.+?)' for (.+)$/)
      if match
        method_name = match[1]
        object_info = match[2].gsub(/#<.*?>/, 'object')
        "missing method '#{method_name}' on #{object_info}"
      else
        message
      end
    end
  end
end
