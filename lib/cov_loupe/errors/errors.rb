# frozen_string_literal: true

require_relative '../staleness/staleness_message_formatter'

module CovLoupe
  # Error hierarchy for cov-loupe.
  #
  # All custom errors inherit from CovLoupe::Error and implement `user_friendly_message`
  # for mode-appropriate display (CLI gets helpful tips, MCP gets structured text).
  #
  # Hierarchy:
  #   Error
  #     ├── ConfigurationError     — setup/config problems
  #     │   └── LoggingError       — logging target setup/write problems
  #     ├── UnknownError           — unclassified exceptions
  #     ├── TextEncodingError      — encoding conversion failures outside coverage loading
  #     ├── PredicateError         — user predicate failed to load or run
  #     ├── FileError              — file/path problems
  #     │     ├── FileNotFoundError
  #     │     ├── FilePermissionError
  #     │     ├── NotAFileError
  #     │     └── CoverageFileNotFoundError  — adds CLI-specific help tips
  #     ├── UsageError             — command-line usage mistakes
  #     └── CoverageDataError      — coverage data problems
  #           ├── CorruptCoverageDataError
  #           ├── CoverageDataStaleError      — single-file staleness
  #           └── CoverageDataProjectStaleError — project-wide staleness
  #
  # Base error class for all cov-loupe errors
  #
  # @api public
  class Error < StandardError
    attr_reader :original_error

    def initialize(message = nil, original_error = nil)
      @original_error = original_error
      super(message)
    end

    def user_friendly_message
      message
    end

    # The backtrace most useful for diagnosis: the wrapped exception's, which points at the
    # actual failure site (e.g., inside a predicate), rather than where it was re-raised.
    #
    # @api private
    def diagnostic_backtrace
      original_error&.backtrace || backtrace
    end
  end

  # Configuration or setup related errors
  #
  # @api public
  class ConfigurationError < Error
    def user_friendly_message
      "Configuration error: #{message}"
    end
  end

  # @api public
  class LoggingError < ConfigurationError
    attr_reader :target

    def initialize(target, message, original_error = nil)
      @target = target
      super("Unable to use log target #{target.inspect}: #{message}", original_error)
    end
  end

  # Error wrapper when the root cause is unknown or unclassified.
  #
  # @api public
  class UnknownError < Error
    def user_friendly_message
      "An unexpected error occurred: #{message}"
    end
  end

  # Text could not be converted between encodings, outside coverage loading (for example,
  # output written to a stream that transcodes to a non-UTF-8 encoding).
  #
  # @api public
  class TextEncodingError < Error
    def user_friendly_message
      "Text encoding error: #{message}"
    end
  end

  # A user-supplied predicate failed to load or raised while running. Distinct from
  # CoverageDataError so callers (and AI agents) fix the predicate, not the coverage data.
  #
  # @api public
  class PredicateError < Error
    def user_friendly_message
      "Predicate error: #{message}"
    end
  end

  # File or path related errors
  #
  # @api public
  class FileError < Error
    def user_friendly_message
      "File error: #{message}"
    end
  end

  # More specific file errors
  #
  # @api public
  class FileNotFoundError < FileError; end
  # @api public
  class FilePermissionError < FileError; end
  # @api public
  class NotAFileError < FileError; end

  # @api public
  class CoverageFileNotFoundError < FileError
    def user_friendly_message
      base = "File error: #{message}"

      # Only add helpful tips in CLI and library modes, not MCP mode
      unless CovLoupe.context.mcp_mode?
        base += <<~HELP


          Try one of the following:
            - cd to a directory containing coverage/coverage.json
            - Specify a coverage file: cov-loupe -c PATH
            - Use -h for help: cov-loupe -h
        HELP
      end

      base
    end
  end

  # Coverage data related errors
  #
  # @api public
  class CoverageDataError < Error
    def user_friendly_message
      "Coverage data error: #{message}"
    end
  end

  # @api public
  class CorruptCoverageDataError < CoverageDataError
    def user_friendly_message
      "Corrupt coverage data: #{message}"
    end
  end

  # Shared module for stale error formatting
  #
  # @api private
  module StalenessFormatterMixin
    private def formatter
      @formatter ||= StalenessMessageFormatter.new(
        cov_timestamp:      @cov_timestamp,
        coverage_file_path: @coverage_file_path
      )
    end
  end
  private_constant :StalenessFormatterMixin

  # Coverage data is present but appears stale compared to source files
  #
  # @api public
  class CoverageDataStaleError < CoverageDataError
    include StalenessFormatterMixin

    attr_reader :file_path, :file_mtime, :cov_timestamp, :src_len, :cov_len, :coverage_file_path

    def initialize(message = nil, original_error = nil, file_path: nil, file_mtime: nil,
      cov_timestamp: nil, src_len: nil, cov_len: nil, coverage_file_path: nil)
      @file_path = file_path
      @file_mtime = file_mtime
      @cov_timestamp = cov_timestamp
      @src_len = src_len
      @cov_len = cov_len
      @coverage_file_path = coverage_file_path
      super(message || default_message, original_error)
    end

    def user_friendly_message
      "Coverage data stale: #{message}" + formatter.format_single_file_details(
        file_path:  @file_path,
        file_mtime: @file_mtime,
        src_len:    @src_len,
        cov_len:    @cov_len
      )
    end

    private def default_message
      fp = file_path || 'file'
      "Coverage data appears stale for #{fp}"
    end
  end

  # Project-level stale coverage (global) — coverage timestamp older than
  # one or more source files, or new tracked files missing from coverage.
  #
  # @api public
  class CoverageDataProjectStaleError < CoverageDataError
    include StalenessFormatterMixin

    attr_reader :cov_timestamp, :newer_files, :missing_files, :deleted_files,
      :length_mismatch_files, :unreadable_files, :coverage_file_path

    def initialize(message = nil, original_error = nil, cov_timestamp: nil, newer_files: [],
      missing_files: [], deleted_files: [], length_mismatch_files: [], unreadable_files: [],
      coverage_file_path: nil)
      super(message || default_message, original_error)
      @cov_timestamp = cov_timestamp
      @newer_files = Array(newer_files)
      @missing_files = Array(missing_files)
      @deleted_files = Array(deleted_files)
      @length_mismatch_files = Array(length_mismatch_files)
      @unreadable_files = Array(unreadable_files)
      @coverage_file_path = coverage_file_path
    end

    def user_friendly_message
      base = "Coverage data stale (project): #{message}"
      base + formatter.format_project_details(
        newer_files:           @newer_files,
        missing_files:         @missing_files,
        deleted_files:         @deleted_files,
        length_mismatch_files: @length_mismatch_files,
        unreadable_files:      @unreadable_files
      )
    end

    private def default_message
      'Coverage data appears stale for project'
    end
  end

  # Command line usage errors
  #
  # @api public
  class UsageError < Error
    # @api private
    def self.for_subcommand(usage_fragment)
      new("Usage: cov-loupe #{usage_fragment}")
    end

    def user_friendly_message
      message
    end
  end
end
