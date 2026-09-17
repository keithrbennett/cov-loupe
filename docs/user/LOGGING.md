# Logging

cov-loupe writes diagnostics through `CovLoupe::Logger`. The default target is
`./cov_loupe.log`; use `--log-file`/`-l`, `CovLoupe.default_log_file`, or
`CovLoupe.active_log_file` to choose another target. `stderr` is supported, `:off`
disables logging, and `stdout` is not permitted because it would corrupt CLI output
or the MCP JSON-RPC stream.

## Log file initialization and target testing

Logger setup performs a best-effort probe of file targets so configuration failures
are detected when the logger is initialized rather than after a long-running process
eventually needs to write a diagnostic:

- If the target file already exists, cov-loupe opens it in append mode and closes it
  to verify that it is accessible for logging.
- If the target file does not exist, cov-loupe creates it exclusively, closes it, and
  removes it immediately. This tests the directory and file permissions without
  leaving an empty log file behind in the normal case.
- The probe result is cached for the logger instance. A failed probe is not retried
  for every later message.
- The persistent log file is created by the underlying logger on the first actual
  log write.

Probe failures are reported immediately according to the active mode. Library mode
raises a `CovLoupe::LoggingError`; CLI mode emits a warning to `stderr`; and MCP mode
reports a logging failure as an `isError: true` tool result for every affected tool
call (and emits a startup diagnostic to `stderr` because no tool result exists during
startup). Startup warnings and fallback-write warnings are each emitted at most
once per logger instance.

The probe is necessarily best-effort: filesystem permissions or availability can
change between the probe and the first write. If the configured target later fails,
cov-loupe uses its logging error-handling path. The fallback diagnostic target is
`COV-LOUPE-LOG-ERROR.log` when the fallback can be written. In MCP mode, each
affected tool call attempts to append its diagnostic there, so a server with a
persistently invalid target can grow this fallback file until the configuration is
corrected or logging is disabled with `:off`.

MCP tool-execution errors reach cov-loupe's logger, but argument-validation failures
emitted by the MCP SDK before cov-loupe runs do not.
