# Logging

cov-loupe writes diagnostics through `CovLoupe::Logger`. CLI and MCP sessions use
`stderr` by default; library sessions have logging disabled by default. Use
`--log-file`/`-l`, `CovLoupe.default_log_file`, or `CovLoupe.active_log_file` to
choose another target. A file path enables persistent logging, `stderr` is
supported explicitly, `:off` disables logging, and `stdout` is not permitted
because it would corrupt CLI output or the MCP JSON-RPC stream.

File logging is intentionally explicit and has no built-in rotation. Users who
choose a file target are responsible for cleanup or external log rotation.

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
- An explicitly configured file is created by the underlying logger on the first
  actual log write.

Probe failures are reported immediately according to the active mode. Library mode
raises a `CovLoupe::LoggingError`; CLI mode emits a warning to `stderr`; and MCP mode
reports a logging failure as an `isError: true` tool result for every affected tool
call (and emits a startup diagnostic to `stderr` because no tool result exists during
startup). There is no implicit fallback file. If an explicitly configured file
fails during a CLI write, cov-loupe warns on `stderr`; direct MCP and library
logging calls raise `CovLoupe::LoggingError`. MCP tool handling catches a logging
failure so the original operation error remains the tool result.

The probe is necessarily best-effort: filesystem permissions or availability can
change between the probe and the first write. If the configured target later fails,
cov-loupe uses its mode-specific logging error-handling path. Logging failures are
secondary diagnostics and must not replace the original operation error, especially
for MCP tool calls. `safe_log` suppresses logging failures when a diagnostic is not
allowed to interrupt the operation.

MCP tool-execution errors reach cov-loupe's logger, but argument-validation failures
emitted by the MCP SDK before cov-loupe runs do not.
