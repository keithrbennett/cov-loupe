# frozen_string_literal: true

module CovLoupe
  # One-time deprecation warnings for renamed public API.
  #
  # cov-loupe originally spoke of the "resultset" everywhere, because
  # .resultset.json was the only input it could read. Now that coverage.json
  # is read as well, the accurate name for the input is the coverage file,
  # and the old names are deprecated (see docs/user/migrations/README.md).
  #
  # Each distinct old/new pair warns once per process, so a deprecated
  # option used in a loop does not flood the output.
  #
  # Warnings go to the log, and additionally to stderr outside MCP mode.
  # stdout is never used: it carries command output in CLI mode and the
  # JSON-RPC stream in MCP mode.
  module Deprecation
    # The release that removes the deprecated names.
    REMOVAL_VERSION = '7.0.0'

    class << self
      # Whether warnings are emitted. Setting this to false silences them
      # without changing behavior, which specs use to keep output clean.
      attr_writer :enabled

      def enabled?
        @enabled = true unless defined?(@enabled)
        @enabled
      end

      # Warn that +old+ has been renamed to +new+.
      #
      # @param old [String] the deprecated name, as a user would write it
      # @param new [String] the replacement name
      # @param removed_in [String] version that drops the deprecated name
      # @return [nil]
      def warn(old, new, removed_in: REMOVAL_VERSION)
        return unless enabled?

        message = "cov-loupe: #{old} is deprecated and will be removed in v#{removed_in}; " \
                  "use #{new} instead."
        emit(message) if record(message)
        nil
      end

      # Forget which warnings have been emitted, so they warn again.
      # Intended for specs; harmless elsewhere.
      def reset!
        mutex.synchronize { warned.clear }
        nil
      end

      # Records the message and reports whether it is the first time it was
      # seen, so each distinct deprecation warns exactly once.
      private def record(message)
        mutex.synchronize do
          next false if warned.key?(message)

          warned[message] = true
        end
      end

      private def emit(message)
        CovLoupe.logger&.safe_log(message)
        # Callers reading stdout must not see this; stderr is safe in both
        # CLI and library mode, but MCP clients treat it as server noise.
        Kernel.warn(message) unless CovLoupe.context.mcp_mode?
      rescue
        # A deprecation notice must never break the call it is attached to.
        nil
      end

      private def warned
        @warned ||= {}
      end

      private def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
