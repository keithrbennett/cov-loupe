# Logging

[Back to main README](../../README.md)

cov-loupe writes diagnostics to the logger of the active context. CLI and MCP sessions log to
`stderr` by default; library sessions have logging disabled by default.

## Choosing a log target

Set the target with `--log-file`/`-l` in the CLI and MCP server, or with
`CovLoupe.default_log_file` or `CovLoupe.active_log_file` in the library. Values:

- a file path - persistent logging
- `stderr`
- `off` - disable logging (use `./off` for a file named `off`)

`stdout` is not allowed, because log output would corrupt CLI output or the MCP JSON-RPC stream.

A `CoverageModel` keeps the logger of the context it was created in, so create the model after
changing the target (or inside `CovLoupe.with_context`).

File logging has no built-in rotation. If you log to a file, clean it up or rotate it externally.

## What the CLI logs

- The `CLI parameters` line is written only to a log file, never to `stderr`. A log file gets
  one for each run whose options are valid and whose subcommand, if any, is known.
- Each error is printed to stderr once, as the user-facing message, and is not also logged
  there. With `--error-mode debug`, the full stack trace follows the message (only its first
  5 lines when logging to a file, which gets the full trace).
- With a log file, each error is also logged to the file, unless `--error-mode off` is set.
- Invalid options and option values are rejected before logging is set up, so they appear only
  on stderr. An unknown subcommand and other usage errors found by the subcommand, such as a
  missing path, are logged to the file.
- Warnings and diagnostics about the coverage data can appear on stderr with either target.

## Concurrent processes and agents

Avoid having concurrent agents or processes write to the same log file. This applies to CLI
processes, MCP server processes, and independent library users or contexts. The underlying
logger appends to the file, so concurrent entries are usually preserved, but cov-loupe provides
no cross-process file locking and no guaranteed ordering. Entries may appear out of order or
interleaved, particularly on network filesystems or if the file is rotated while processes are
still running.

Give each concurrent worker its own log target, for example `logs/cov-loupe-agent-1.log` and
`logs/cov-loupe-agent-2.log`:

- **CLI and MCP:** pass each process a different `--log-file` value.
- **Library, separate processes:** set a different `CovLoupe.default_log_file` in each process.
- **Library, threads or fibers in one process:** `default_log_file=` is process-wide, so set
  `CovLoupe.active_log_file` (fiber-local) instead, or run each worker's code inside
  `CovLoupe.with_context(CovLoupe.create_context(log_target: ...))`.

Within a single process, calls that share one logger are serialized by the underlying Ruby logger.

## Log file initialization and target testing

When a logger is set up, cov-loupe probes a file target, so that a bad target is
detected immediately rather than when a long-running process first needs to write a
diagnostic:

- If the target file already exists, cov-loupe opens it in append mode and closes it
  to verify that it is accessible for logging.
- If the target file does not exist, cov-loupe creates it exclusively, closes it, and
  removes it immediately. This tests the directory and file permissions without
  leaving an empty log file behind in the normal case.
- The probe result is cached for the logger instance. A failed probe is not retried
  for every later message.
- An explicitly configured file is created by the underlying logger on the first
  actual log write.

A probe failure is reported immediately, in a way that depends on the mode:

- **Library:** raises `CovLoupe::LoggingError`.
- **CLI:** prints a warning to `stderr`.
- **MCP:** returns an `isError: true` tool result for every affected tool call. At startup,
  when there is no tool result to carry it, the server prints a diagnostic to `stderr`.

There is no fallback file.

The probe is best-effort: permissions or availability can change between the probe and the
first write. If a configured file fails during a later write, the CLI warns on `stderr`, and
MCP and library logging calls raise `CovLoupe::LoggingError`. A logging failure never replaces
the error of the operation being logged: MCP tool handling catches it so the original error
remains the tool result, and diagnostics that must not interrupt an operation suppress
logging failures entirely.

MCP tool-execution errors reach cov-loupe's logger, but argument-validation failures
emitted by the MCP SDK before cov-loupe runs do not.
