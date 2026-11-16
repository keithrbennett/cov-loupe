# frozen_string_literal: true

# Helpers for managing control flow in RSpec tests.
module ControlFlowHelpers
  # Execute a block that's expected to call exit() without terminating the test.
  # Useful for testing CLI commands that normally exit.
  # Returns the exit status code if exit was called, otherwise returns the block's value.
  #
  # Examples:
  #   status = swallow_system_exit { CovLoupe.run(['--help']) }
  #   expect(status).to eq(0)  # --help calls exit(0)
  #
  #   result = swallow_system_exit { some_computation }
  #   expect(result).to eq(expected_value)  # no exit, returns block value
  def swallow_system_exit
    yield
  rescue SystemExit => e
    e.status
  end
end
