# Logging

[Back to main README](../../README.md)

cov-loupe writes diagnostics to the logger of the active context. CLI and MCP sessions use
`stderr` by default; library sessions have logging disabled by default. Use
`--log-file`/`-l`, `CovLoupe.default_log_file`, or `CovLoupe.active_log_file` to
choose another target. A `CoverageModel` keeps the logger of the context it was created in, so
create the model after changing the target (or inside `CovLoupe.with_context`). A file path enables persistent logging, `stderr` is
supported explicitly, `off` disables logging (use `./off` for a file literally named `off`), and `stdout` is not permitted
because it would corrupt CLI output or the MCP JSON-RPC stream.

In the CLI, the `CLI parameters` line is written only to a log file, never to
`stderr`. An error is printed to stderr once as the user-facing message rather
than also being logged there; with `--error-mode debug`, the CLI follows it with
the full stack trace (only its first 5 lines when logging to a file, which gets the
full trace). Warnings and diagnostics about the coverage data can still
appear on stderr. With a file target, the file receives the
parameters line (for each run that gets past option parsing, including the
default report) and the logged error (unless `--error-mode off` is used), and
the user-facing message still appears on stderr. Invalid options and option
values are rejected before logging is set up, so they appear only on stderr;
other usage errors, such as an unknown subcommand or misplaced global options,
are logged to the file.

File logging is intentionally explicit and has no built-in rotation. Users who
choose a file target are responsible for cleanup or external log rotation.

## Concurrent processes and agents

Do not configure multiple concurrent agents or processes to write to the same
log file when separate log files are practical. This applies to CLI processes,
MCP server processes, and independent library users or contexts. The underlying
logger appends to the file, so concurrent entries will usually be preserved, but
cov-loupe does not provide cross-process file locking or guaranteed ordering of
entries. Messages may therefore appear out of order or become interleaved,
particularly on network filesystems or if the file is rotated while processes
are still running.

Use a distinct log target for each concurrent worker, for example
`logs/cov-loupe-agent-1.log` and `logs/cov-loupe-agent-2.log`. For CLI and MCP,
pass each process a different `--log-file` value. For library usage, set a
different `CovLoupe.default_log_file` in each worker process; `default_log_file=`
is process-wide, so workers that are threads or fibers in one process should
instead set `CovLoupe.active_log_file` (fiber-local) or run their work inside
`CovLoupe.with_context(CovLoupe.create_context(log_target: ...))`. Calls sharing one logger within a single process remain
serialized by the underlying Ruby logger.

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
