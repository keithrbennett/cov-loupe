# Error Handling Guide

[Back to main README](../../README.md)

Error handling differs by usage mode:

## CLI Mode

Errors are displayed as user-friendly messages without stack traces:

```bash
$ cov-loupe summary nonexistent.rb
Coverage data error: No coverage entry found for /path/to/project/nonexistent.rb

$ cov-loupe s nonexistent.rb
Coverage data error: No coverage entry found for /path/to/project/nonexistent.rb
```

For debugging, use `--error-mode debug` to show stack traces. With the default `stderr` log target or `--log-file off`, the full backtrace is printed after the error message. When logging to a file, the file gets the full backtrace and stderr shows its first 5 lines:

```bash
$ cov-loupe --error-mode debug summary nonexistent.rb
$ cov-loupe --error-mode debug s nonexistent.rb
```

## Library Mode

Calls to `CovLoupe::CoverageModel` raise custom exceptions (subclasses of `CovLoupe::Error`) rather than printing or logging them; rescue them in your code.

One exception: an invalid `sort_order` value, or an invalid `output_chars` value when there are rows to format, raises Ruby's `ArgumentError`, which rescuing `CovLoupe::Error` does not catch. See [Exception Types](LIBRARY_API.md#exception-types).

Library logging is off by default. To keep the diagnostics cov-loupe logs along the way, such as skipped coverage rows, give the context a log target:

```ruby
context = CovLoupe.create_context(log_target: 'cov_loupe.log')

CovLoupe.with_context(context) do
  model = CovLoupe::CoverageModel.new
  begin
    model.summary_for('missing.rb')
  rescue CovLoupe::CoverageEntryNotFoundError => e
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

MCP clients can detect argument-validation and tool-execution failures by checking the result's
`isError` field. Protocol- and dispatch-level failures do not contain a tool result.

Error messages in tool results are user-friendly and, by default, contain no stack traces.
cov-loupe logs tool-execution errors to `stderr` by default; use `--log-file` to log them to a
file instead (see [Log file initialization and target testing](LOGGING.md#log-file-initialization-and-target-testing)).
Argument-validation failures are produced by the MCP SDK and never reach cov-loupe's logger.

## Stale Coverage Errors

When strict staleness checking is enabled (`--raise-on-stale true` in the CLI, or `CovLoupe::CoverageModel.new(raise_on_stale: true)` in the library), stale coverage raises an error:

- **Single-file queries** (`summary`, `raw`, `uncovered`, `detailed`) raise `CoverageDataStaleError` if the source file appears newer than the coverage data or the line counts differ. A deleted file raises `FileNotFoundError` instead, and an unreadable file `FileError`.
- **Project queries** (`list`, `totals`, the CLI's default report, and `validate` predicates that call `list` or `project_totals`) raise `CoverageDataProjectStaleError` if any file in the coverage data (only those matching the file globs, when set) is newer, deleted, has mismatched line counts, or is unreadable. When file globs are set, a matching file that is not in the coverage data also raises it.
    - Its `user_friendly_message` (what the CLI prints) lists the affected files by category. `#message` is a short summary, followed by a [wrong-root hint](TROUBLESHOOTING.md#the-project-root-may-be-wrong) when most files were not found under the project root.
    - A project query also raises if a coverage row would be skipped, instead of skipping it with a warning. It raises the error recorded for the first skipped row, a `CoverageDataError` such as `CorruptCoverageDataError` or `AmbiguousCoverageEntryError`.
- The staleness errors and the skipped-row errors are all subclasses of `CoverageDataError`; rescue that to catch them. `FileNotFoundError` and `FileError` are not; rescue `CovLoupe::Error` to catch every error above.

The single-file error message is detailed and includes:

- The file and coverage times (UTC and local) and line counts
- How much newer the file is than the coverage data
- The absolute path to the `coverage.json` used

**Example excerpt:**

```
Coverage data stale: Coverage data appears stale for lib/foo.rb
File     - time: 2025-09-16T14:03:22Z (local 2025-09-16T07:03:22-07:00), lines: 226
Coverage - time: 2025-09-15T21:11:09Z (local 2025-09-15T14:11:09-07:00), lines: 220

Delta    - file is +60733s newer than coverage
Coverage file - /path/to/project/coverage/coverage.json
```
