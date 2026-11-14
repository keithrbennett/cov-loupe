# frozen_string_literal: true

module CovLoupe
  # Process exit codes used by the CLI. Keep docs/user/CLI_USAGE.md in sync.
  #
  # @api public
  module ExitCodes
    SUCCESS           = 0 # command succeeded; for `validate`, the predicate passed
    ERROR             = 1 # runtime error (missing/stale/corrupt coverage data, bad path, etc.)
    USAGE             = 2 # invalid options, arguments, or configuration
    VALIDATION_FAILED = 3 # `validate`: the predicate ran and returned a falsy value
    PREDICATE_ERROR   = 4 # `validate`: the predicate itself could not be loaded or raised an error
  end

  # Raised wherever the CLI ends with an exit status. As a SystemExit it ends the process under
  # CovLoupe.run; CovLoupe.execute rescues it, and only it, to return the status instead.
  #
  # @api private
  class CliExit < SystemExit
    # Keep SystemExit's message, rather than the class name a subclass gets by default.
    def message = 'exit'
  end
end
