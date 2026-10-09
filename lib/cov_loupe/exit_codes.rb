# frozen_string_literal: true

module CovLoupe
  # Process exit codes used by the CLI. Keep docs/user/CLI_USAGE.md in sync.
  module ExitCodes
    SUCCESS           = 0 # command succeeded; for `validate`, the predicate passed
    ERROR             = 1 # runtime error (missing/stale/corrupt coverage data, bad path, etc.)
    USAGE             = 2 # invalid options, arguments, or configuration
    VALIDATION_FAILED = 3 # `validate`: the predicate ran and returned a falsy value
    PREDICATE_ERROR   = 4 # `validate`: the predicate itself could not be loaded or raised an error
  end
end
