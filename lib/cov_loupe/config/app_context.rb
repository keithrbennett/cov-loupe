# frozen_string_literal: true

require_relative 'logger'

module CovLoupe
  # Immutable configuration context for a CovLoupe session.
  #
  # Bundles error handling, logging, and mode into a single object that can be
  # scoped to a thread (via CovLoupe.with_context) or used globally.
  #
  # Implemented as a Data class (introduced in Ruby 3.2) for immutability and structural equality.
  # The custom #with method ensures the derived `logger` field is regenerated when
  # log_target or mode changes, since the logger depends on both.
  AppContext = Data.define(:error_handler, :log_target, :mode, :app_config, :logger) do
    def initialize(error_handler:, log_target: nil, mode: :library, app_config: nil, logger: nil)
      logger ||= Logger.new(target: log_target, mode: mode)
      super
    end

    # Overrides Data#with to handle derived state.
    #
    # Since the `logger` depends on `log_target` and `mode`, we must ensure
    # it is regenerated if either of those fields are changed. Otherwise,
    # the new instance would point to the old logger (e.g. logging to the
    # wrong file).
    def with(**kwargs)
      target_changed = kwargs.key?(:log_target) && kwargs[:log_target] != log_target
      mode_changed = kwargs.key?(:mode) && kwargs[:mode] != mode

      if target_changed || mode_changed
        target = kwargs.fetch(:log_target, log_target)
        new_mode = kwargs.fetch(:mode, mode)
        kwargs[:logger] = Logger.new(target: target, mode: new_mode)
      end
      super
    end

    def mcp_mode?
      mode == :mcp
    end

    def cli_mode?
      mode == :cli
    end

    def library_mode?
      mode == :library
    end
  end
end
