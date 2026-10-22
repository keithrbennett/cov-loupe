# frozen_string_literal: true

# Shared test helpers for I/O operations (capturing or suppressing stdout/stderr).
module TestIOHelpers
  # Redirect stdout and stderr for the duration of the block.
  # Returns [block_return_value, stdout_string, stderr_string].
  # If swallow_exit: true, SystemExit is rescued and returned as the block value.
  def capture_io(swallow_exit: false)
    old_out, old_err = $stdout, $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    result = begin
      yield
    rescue SystemExit => e
      raise unless swallow_exit

      e
    end
    [result, $stdout.string, $stderr.string]
  ensure
    $stdout = old_out
    $stderr = old_err
  end

  # Runs the block with Encoding.default_external set to UTF-8. Error messages show paths with
  # String#inspect, which escapes non-ASCII unless it is UTF-8, and coverage.json with non-ASCII
  # paths is read in it; pin it so examples with non-ASCII data do not depend on the locale.
  def with_utf8_default_external
    original = Encoding.default_external
    assign_default_external(Encoding::UTF_8)
    yield
  ensure
    assign_default_external(original)
  end

  # Assigning Encoding.default_external warns; silence only the assignment, because the CLI
  # prints errors with Kernel#warn, which is silent while $VERBOSE is nil.
  def assign_default_external(encoding)
    verbose = $VERBOSE
    $VERBOSE = nil
    Encoding.default_external = encoding
  ensure
    $VERBOSE = verbose
  end

  # Redirect stdout and stderr for the duration of the block and discard them.
  # Returns the block's return value.
  def suppress_io(&)
    capture_io(&)[0]
  end

  # Capture only stderr for the duration of the block; swallows SystemExit.
  # Returns the captured stderr string.
  def capture_stderr(&)
    _result, _out, err = capture_io(swallow_exit: true, &)
    err
  end

  # Run a command and return its stdout string (stderr is discarded).
  # @param command [CovLoupe::Commands::BaseCommand] The command instance to execute
  # @param args [Array] The arguments to pass to execute
  # @return [String] The captured stdout string
  def capture_command_output(command, args)
    _result, out, _err = capture_io { command.execute(args.dup) }
    out
  end
end
