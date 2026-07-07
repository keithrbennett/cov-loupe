# Error Handling Guide

[Back to main README](../index.md)

Error handling differs by usage mode:

## CLI Mode

Errors are displayed as user-friendly messages without stack traces:

```bash
$ cov-loupe summary nonexistent.rb
File error: No coverage data found for the specified file

$ cov-loupe s nonexistent.rb
File error: No coverage data found for the specified file
```

For debugging, use the `--error-mode debug` flag to include stack traces in log output and display the first 5 lines of the backtrace in CLI output:

```bash
$ cov-loupe --error-mode debug summary nonexistent.rb
$ cov-loupe --error-mode debug s nonexistent.rb
```

## Library Mode

Calls to `CovLoupe::CoverageModel` raise custom exceptions you can handle programmatically:

```ruby
handler = CovLoupe::ErrorHandlerFactory.for_library  # disables CLI-style logging
context = CovLoupe.create_context(error_handler: handler)

CovLoupe.with_context(context) do
  model = CovLoupe::CoverageModel.new
  begin
    model.summary_for('missing.rb')
  rescue CovLoupe::FileError => e
    puts "Handled gracefully: #{e.user_friendly_message}"
  end
end
```

Available exception classes:
- `CovLoupe::Error` - Base error class
- `CovLoupe::FileError` - Requested file not in coverage data
- `CovLoupe::FileNotFoundError` - File does not exist on disk (subclass of `FileError`)
- `CovLoupe::FilePermissionError` - File permission denied (subclass of `FileError`)
- `CovLoupe::CoverageDataError` - Invalid or missing coverage data
- `CovLoupe::ResultsetNotFoundError` - Coverage data file not found (subclass of `CoverageDataError`)
- `CovLoupe::CoverageDataStaleError` - Coverage data is stale (when `raise_on_stale: true`)
- `CovLoupe::CoverageDataProjectStaleError` - Project-wide staleness error
- `CovLoupe::ConfigurationError` - Configuration problems
- `CovLoupe::UsageError` - Command usage errors

## MCP Server Mode

Errors are surfaced in one of two ways, depending on where the failure occurs:

- **Tool-result error flag** - Failed tool *executions* (bad path, invalid predicate, stale coverage, etc.) return a `tools/call` result with `isError: true`. MCP clients can detect the failure programmatically by checking the `isError` field.
- **JSON-RPC error** - Protocol-level failures and arguments that fail MCP input-schema validation (unknown tool, missing required argument, invalid enum value such as `format` or `sort_order`) return a JSON-RPC `error` response, *not* a `tools/call` result with `isError: true`.
- **Logging enabled** - Errors go to `cov_loupe.log` in the current directory by default
- **Clean error messages** - User-friendly messages, no stack traces by default

## Custom Error Handlers

Library usage can opt into different logging behavior by installing a custom handler on the active context:

```ruby
handler = CovLoupe::ErrorHandler.new(
  log_errors: true,         # Enable logging when embedding
  show_stack_traces: false  # Keep error messages clean
)

context = CovLoupe.create_context(error_handler: handler)

CovLoupe.with_context(context) do
  model = CovLoupe::CoverageModel.new
  model.summary_for('lib/cov_loupe/model/model.rb')
end
```

## Stale Coverage Errors

When strict staleness checking is enabled (`--raise-on-stale`), the model (and CLI) raise a `CoverageDataStaleError` if a source file appears newer than the coverage data or the line counts differ.

- Enable per instance: `CovLoupe::CoverageModel.new(raise_on_stale: true)`

The error message is detailed and includes:

- File and Coverage times (UTC and local) and line counts
- A delta indicating how much newer the file is than coverage
- The absolute path to the `.resultset.json` used

**Example excerpt:**

```
Coverage data stale: Coverage data appears stale for lib/foo.rb

File     - time: 2025-09-16T14:03:22Z (local 2025-09-16T07:03:22-07:00), lines: 226
Coverage - time: 2025-09-15T21:11:09Z (local 2025-09-15T14:11:09-07:00), lines: 220
Delta    - file is +123s newer than coverage
Resultset - /path/to/project/coverage/.resultset.json
```
