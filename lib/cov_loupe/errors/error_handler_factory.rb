# frozen_string_literal: true

require_relative 'error_handler'

module CovLoupe
  # Factory methods for creating ErrorHandler instances tuned to each operating mode.
  #
  # The factory pattern ensures each mode gets consistent defaults:
  #   - CLI:       :log mode (errors logged, no stack traces unless requested)
  #   - Library:   :off mode (no logging side effects, let consumers handle errors)
  #   - MCP Server: :log mode (errors logged for server debugging)
  #
  # @api private
  module ErrorHandlerFactory
    # Error handler for CLI usage
    # - Logs errors for debugging
    # - Shows stack traces only when explicitly requested
    # - Suitable for user-facing command line interface
    def self.for_cli(error_mode: :log)
      ErrorHandler.new(error_mode: error_mode)
    end

    # Error handler for library usage
    # - No logging by default (avoids side effects in consuming applications)
    # - No stack traces (libraries should let consumers handle error display)
    # - Suitable for embedding in other applications
    def self.for_library(error_mode: :off)
      ErrorHandler.new(error_mode: error_mode)
    end

    # Error handler for MCP server usage
    # - Logs errors for server debugging
    # - Shows stack traces only when explicitly requested
    # - Suitable for long-running server processes
    def self.for_mcp_server(error_mode: :log)
      ErrorHandler.new(error_mode: error_mode)
    end
  end
end
