# frozen_string_literal: true

require_relative '../errors/errors'

module CovLoupe
  # Configuration container for application options.
  #
  # Populated by ConfigParser from CLI arguments or constructed directly for MCP mode.
  # Provides convenience methods (model_options, formatter_options) that extract
  # the relevant subset of config for initializing CoverageModel and SourceFormatter.
  #
  # Mutable by design: callers may adjust fields during setup before handing the
  # config object off to CLI or MCP entry points.
  #
  # All enum values are stored as symbols (:table, :json, :descending, etc.)
  # for consistent comparison throughout the codebase.
  AppConfig = Struct.new(
    :root,
    :resultset,
    :format,
    :sort_order,
    :source_mode,
    :source_context,
    :color,
    :error_mode,
    :raise_on_stale,
    :tracked_globs,
    :log_file,
    :mode,
    :output_chars
  ) do
    # Set sensible defaults - ALL SYMBOLS FOR ENUMS
    def initialize(
      root: '.',
      resultset: nil,
      format: :table,
      sort_order: :descending,
      source_mode: nil,
      source_context: 2,
      color: $stdout.tty?,
      error_mode: :log,
      raise_on_stale: false,
      tracked_globs: nil,
      log_file: nil,
      mode: :cli,
      output_chars: :default
    )
      # Default to empty array (show all files in resultset and don't look for files lacking coverage data)
      # Users should set COV_LOUPE_OPTS to match SimpleCov track_files patterns
      tracked_globs = [] if tracked_globs.nil?
      super
    end

    # Convenience method for CoverageModel initialization
    def model_options
      {
        root:           root,
        resultset:      resultset,
        raise_on_stale: raise_on_stale,
        tracked_globs:  tracked_globs,
      }
    end

    # Convenience method for SourceFormatter initialization
    def formatter_options
      {
        color_enabled: color,
        output_chars:  output_chars,
      }
    end

    # Validate configuration after all options have been merged.
    # Raises ConfigurationError for values that are unconditionally invalid.
    def validate!
      self.class.validate_log_file!(log_file)
      self
    end

    # Shared validation for any log target value.
    def self.validate_log_file!(value)
      return unless value.to_s.strip.downcase == 'stdout'

      raise ConfigurationError,
        'Logging to stdout is not permitted because it corrupts command output. ' \
        "Use 'stderr', a file path, or ':off' to disable logging."
    end
  end
end
