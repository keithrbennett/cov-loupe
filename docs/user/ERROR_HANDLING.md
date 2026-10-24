# Error Handling Guide

[Back to main README](../../README.md)

Error handling differs by usage mode:

## CLI Mode

Errors are displayed as user-friendly messages without stack traces:

```bash
$ cov-loupe summary nonexistent.rb
File error: No coverage entry found for /path/to/project/nonexistent.rb

$ cov-loupe s nonexistent.rb
File error: No coverage entry found for /path/to/project/nonexistent.rb
```

For debugging, use the `--error-mode debug` flag to show stack traces. With the default `stderr` log target or `--log-file off`, the full backtrace is printed after the error message; with a `--log-file` file, the file gets the full backtrace and the CLI output shows its first 5 lines:

```bash
$ cov-loupe --error-mode debug summary nonexistent.rb
$ cov-loupe --error-mode debug s nonexistent.rb
```

## Library Mode

Calls to `CovLoupe::CoverageModel` raise custom exceptions rather than printing or logging them; rescue them in your code. To keep the diagnostics cov-loupe logs along the way, such as skipped coverage rows, give the context a log target:

```ruby
context = CovLoupe.create_context(log_target: 'cov_loupe.log')

CovLoupe.with_context(context) do
  model = CovLoupe::CoverageModel.new
  begin
    model.summary_for('missing.rb')
  rescue CovLoupe::FileError => e
    puts "Handled gracefully: #{e.user_friendly_message}"
  end
end
```

Library calls never consult the context's configured error handler, and the error handler classes and protocol (`handle_error`, `convert_standard_error`) are not public API; see [Public API and Versioning](LIBRARY_API.md#public-api-and-versioning).

See [Exception Types](LIBRARY_API.md#exception-types) for the full exception hierarchy.

## MCP Server Mode

Three failure categories map to two response shapes:

- **Argument validation** - Missing required arguments and invalid enum values such as `format` or `sort_order` return a `tools/call` result with `isError: true`. The MCP SDK rejects these requests before the tool implementation runs.
- **Tool execution** - Bad paths, invalid predicates, stale coverage, and similar cov-loupe errors return a `tools/call` result with `isError: true`.
- **Protocol and dispatch** - Malformed JSON-RPC requests, unknown methods, and unknown tools return a top-level JSON-RPC `error` response rather than a `tools/call` result.

MCP clients can detect argument-validation and tool-execution failures programmatically by checking
the result's `isError` field. Protocol- and dispatch-level failures do not contain a tool result.

- **Logging enabled** - Tool-execution errors handled by cov-loupe go to `stderr` by default; use `--log-file` to choose an explicit persistent file target. See the [logging initialization and target testing guide](LOGGING.md#log-file-initialization-and-target-testing); MCP SDK argument-validation failures do not reach cov-loupe's logger
- **Clean error messages** - User-friendly messages, no stack traces by default

## Stale Coverage Errors

When strict staleness checking is enabled (`--raise-on-stale true`), the model (and CLI) raise a staleness error:

- **Single-file queries** (`summary`, `raw`, `uncovered`, `detailed`) raise `CoverageDataStaleError` if the source file appears newer than the coverage data or the line counts differ.
- **Project queries** (`list`, `totals`, the CLI's default report, and `validate` predicates that call `list` or `project_totals`) raise `CoverageDataProjectStaleError` if any tracked file is newer, missing from coverage (checked only when tracked globs are set), deleted, has mismatched line counts, or is unreadable. Its `user_friendly_message` (what the CLI prints) lists the affected files by category; `#message` is a short summary.
- Both are subclasses of `CoverageDataError`; rescue that to catch either.
- A single-file query for a deleted file raises `FileNotFoundError`, and for an unreadable file `FileError`, rather than a staleness error.
- A project query also raises if a coverage row would be skipped, instead of skipping it with a warning. It raises the error recorded for the first skipped row, usually a `CoverageDataError` but a `FileError` when the source file could not be read; rescue `CovLoupe::Error` to catch both.

- Enable per instance: `CovLoupe::CoverageModel.new(raise_on_stale: true)`

The single-file error message is detailed and includes:

- File and Coverage times (UTC and local) and line counts
- A delta indicating how much newer the file is than coverage
- The absolute path to the `coverage.json` used

**Example excerpt:**

```
Coverage data stale: Coverage data appears stale for lib/foo.rb
File     - time: 2025-09-16T14:03:22Z (local 2025-09-16T07:03:22-07:00), lines: 226
Coverage - time: 2025-09-15T21:11:09Z (local 2025-09-15T14:11:09-07:00), lines: 220

Delta    - file is +60733s newer than coverage
Coverage file - /path/to/project/coverage/coverage.json
```
