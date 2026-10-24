# Advanced Usage Guide

[Back to main README](../../README.md)

> Examples use `clp`, an alias pointed at the demo fixture with partial coverage:
>
> `alias clp='cov-loupe -R docs/fixtures/demo_project'`  # -R = --root
> Run the examples from the root of a cov-loupe checkout, since the alias's path is relative.
>
> Replace `clp` with `cov-loupe` if you want to target your own project/coverage file.
>
> The fixture's coverage timestamp is deliberately set far in the future, so the outputs below — including `--raise-on-stale` / `-S` runs — are reproducible on a fresh clone.

## Table of Contents

- [Advanced MCP Integration](#advanced-mcp-integration)
- [Sorting Coverage Lists with n/a Entries](#sorting-coverage-lists-with-na-entries)
- [Staleness Detection & Validation](#staleness-detection-validation)
- [Advanced Path Resolution](#advanced-path-resolution)
- [Error Handling Strategies](#error-handling-strategies)
- [Custom Ruby Integration](#custom-ruby-integration)
- [CI/CD Integration](#cicd-integration)
- [Advanced Filtering & Glob Patterns](#advanced-filtering-glob-patterns)

---

## Advanced MCP Integration

### MCP Error Handling

The MCP server signals tool-call failures by returning a `tools/call` **result** with `isError: true` (the MCP-spec mechanism for tool errors), carrying the user-friendly message in the response content:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Error: File error: Could not find coverage.json under \"/path/to/project\"; run tests or set --coverage-file option"
      }
    ],
    "isError": true
  }
}
```

This lets MCP clients programmatically distinguish a failed tool call from a successful one. Argument-validation failures also return `isError: true`; a JSON-RPC `error` response is reserved for protocol- and dispatch-level failures such as an unknown tool.

### MCP Server Logging

The MCP server logs tool-execution errors and other cov-loupe diagnostics to `stderr` by default. See the [logging initialization and target testing guide](LOGGING.md#log-file-initialization-and-target-testing) for details about startup probing, append-mode checks, cached failures, and explicit file targets. Argument-validation failures emitted by the MCP SDK before cov-loupe runs do not reach this logger.

To use a persistent log file, specify the `--log-file` (or `-l`) argument wherever and however you configure your MCP server. For example, include `-l /path/to/logfile.log` in your server configuration. To use standard error explicitly, use `-l stderr`. To disable logging entirely, use `-l off` (cross-platform alternative to `/dev/null`).

**Warning:** Explicit log files may grow unbounded in long-running or CI usage. cov-loupe does not rotate them; use external rotation or periodically clean them up.

**Note:** Logging to `stdout` is not permitted in any mode, because it would corrupt command output or the MCP JSON-RPC protocol.

### Testing MCP Server Manually

Use these JSON-RPC commands as smoke tests to confirm that the MCP server launches and responds over stdin with your configuration. They are not exhaustive error-contract tests; see [Testing Your Setup](MCP_INTEGRATION.md#testing-your-setup) for installation checks and [Error Responses](MCP_INTEGRATION.md#error-responses) for the full MCP failure model.

**Note:** CLI flags set defaults for MCP tool calls, but per-request JSON parameters still win. Use `-R`/`-c` when you want server-wide defaults, or pass `root`/`coverage_file` per request.

```sh
# Get version (no parameters needed)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp

# Get file summary (include root parameter in JSON)
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"app/models/order.rb","root":"docs/fixtures/demo_project"}}}' | cov-loupe -m mcp

# List all files with sorting (include root parameter)
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_coverage","arguments":{"sort_order":"ascending","root":"docs/fixtures/demo_project"}}}' | cov-loupe -m mcp

# Get uncovered lines (include root parameter)
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"file_uncovered_lines","arguments":{"path":"app/controllers/orders_controller.rb","root":"docs/fixtures/demo_project"}}}' | cov-loupe -m mcp
```

**Why not use `clp` alias here?** `clp` is useful for CLI subcommands, but MCP calls run a long-lived server process. You can pass `-R` at startup to set defaults, or set `root` explicitly in each JSON request when you want to be explicit or override the defaults.

---

## Sorting Coverage Lists with n/a Entries

When a file has no executable lines, its coverage percentage is reported as `n/a`. In list outputs, `n/a` entries are grouped separately from numeric percentages. The default descending sort order places `n/a` entries above `100%` coverage so they appear earlier in the list, while still keeping low numeric percentages toward the bottom for attention.

If you need to treat `n/a` differently, post-process the JSON output from `list` or `project_coverage` and apply your own sort or filtering rules.

---

## Staleness Detection & Validation {#staleness-detection-validation}

### Understanding Staleness Checks

Staleness checking prevents using outdated coverage data. The behavior is controlled by the boolean `raise_on_stale` setting:

**`raise_on_stale: false` (default)**

- Coverage data is returned even if stale
- Stale indicators are still computed
- Best for exploratory reporting

**`raise_on_stale: true`**

- Raises errors when stale coverage is detected
- Recommended for CI/CD enforcement

### File-Level Staleness

A file is considered stale when any of the following are true:

1. Source file modified after coverage generation (requires timestamps - see [Timestamp Warnings](#timestamp-warnings))
2. Line count differs from coverage array length
3. File exists in coverage but deleted from filesystem
4. Source file could not be read, or its staleness check failed (`unreadable`)

**CLI Usage:**
```sh
# Fail if the file is stale
clp -S true summary app/models/order.rb  # -S = --raise-on-stale
```

> On this fixture the command succeeds even on a fresh clone, because its coverage timestamp is
> future-dated. Against your own project it fails with a stale-data error when a source file's
> mtime postdates the coverage run. (Via the Ruby API this surfaces as
> `CovLoupe::CoverageDataStaleError`.)

**Ruby API:**
```ruby
model = CovLoupe::CoverageModel.new(
  raise_on_stale: true
)

begin
  summary = model.summary_for('app/models/order.rb')
rescue CovLoupe::CoverageDataStaleError => e
  puts "File modified after coverage: #{e.file_path}"
  puts "Coverage timestamp: #{e.cov_timestamp}"
  puts "File mtime: #{e.file_mtime}"
  puts "Source lines: #{e.src_len}, Coverage lines: #{e.cov_len}"
rescue CovLoupe::FileError => e # the file was deleted or could not be read
  puts e.user_friendly_message
end
```

### Project-Level Staleness

Detects system-wide staleness issues:

**Conditions Checked:**

1. **Newer files** - A file in the coverage data that was modified after coverage (requires timestamps - see [Timestamp Warnings](#timestamp-warnings))
2. **Missing files** - Files matching `--tracked-globs` with no coverage data (checked only when globs are set)
3. **Deleted files** - Coverage exists for non-existent files
4. **Line count mismatches** - Source line count differs from the coverage array length
5. **Unreadable files** - Source could not be read, or its staleness check failed

**CLI Usage:**

You can see if _any_ files in the project are stale by running the (implicit here) `list` command
with `--raise-on-stale true` and checking the exit code. The transcript below is illustrative —
captured from a project with files newer than its coverage, not from the demo fixture:

```sh
$ cov-loupe -S true list
Coverage data stale (project): Coverage data appears stale for project
Coverage  - time: 2025-12-10T18:23:00Z (local 2025-12-11T02:23:00+08:00)
Newer files (1):
  - lib/cov_loupe/version.rb
Coverage file - /path/to/project/coverage/coverage.json
$ echo $?
1
```

**Ruby API:**
```ruby
model = CovLoupe::CoverageModel.new(raise_on_stale: true)

begin
  model.list(raise_on_stale: true)
rescue CovLoupe::CoverageDataProjectStaleError => e
  puts "Newer files: #{e.newer_files.join(', ')}"
  puts "Missing from coverage: #{e.missing_files.join(', ')}"
  puts "Deleted but in coverage: #{e.deleted_files.join(', ')}"
  puts "Line count mismatches: #{e.length_mismatch_files.join(', ')}"
  puts "Unreadable: #{e.unreadable_files.join(', ')}"
end
```

### Timestamp Warnings

When coverage data lacks timestamps (e.g., a hand-written or third-party `coverage.json` that passes the `meta.schema_version` check but has no `meta.timestamp`), the project-level commands and tools (CLI `list` and `totals`, MCP `project_coverage` and `project_coverage_totals`) display a warning:

```
WARNING: Coverage timestamps are missing. Time-based staleness checks were skipped.
Files may appear "ok" even if source code is newer than the coverage data.
Check your coverage tool configuration to ensure timestamps are recorded.
```

**What this means:**

- Time-based staleness checks (the `"newer"` indicator) cannot run without timestamps
- Files modified after coverage collection won't be flagged as stale
- Only line count mismatches, deleted or unreadable files, and (with tracked globs) tracked files missing from coverage will be detected
- The `timestamp_status` field in project-level JSON output will show `"missing"` instead of `"ok"`
- Per-file commands and tools show no warning and have no `timestamp_status` field; any command logs an INFO line (on stderr by default) when it loads coverage without a timestamp

**Where it appears:**

- **CLI table format:** On stderr, after the `list` or `totals` output
- **CLI JSON and other structured formats:** On stderr after the output, and in the `timestamp_status` field
- **MCP mode:** In `project_coverage` output with format=table after the exclusions summary
- **MCP JSON:** In the `timestamp_status` field of `project_coverage` and `project_coverage_totals` responses, plus a `warnings` array holding the warning lines

**How to fix:**

SimpleCov always writes `meta.timestamp` in `coverage.json`. If you see this warning:

1. Regenerate coverage data (`bundle exec rspec`)
2. If another tool rewrites `coverage.json`, ensure it preserves `meta.timestamp`

**Example timestamp in `coverage.json`:**
```json
{
  "meta": {
    "schema_version": "1.0",
    "command_name": "RSpec",
    "timestamp": "2024-01-01T00:00:00.000+00:00"
  },
  "coverage": { ... }
}
```

---

## Advanced Path Resolution

### Path Matching Strategy

Path resolution uses two strategies in order:

1. **Exact absolute path match** - Direct lookup using the full path
2. **Relative path resolution** - Strips project root and retries with relative path

On case-insensitive volumes, comparisons are case-normalized; on case-sensitive volumes, case must match exactly.

```ruby
model = CovLoupe::CoverageModel.new(root: '/path/to/project')

model.summary_for('/path/to/project/app/models/order.rb')  # Absolute
model.summary_for('app/models/order.rb')                   # Relative
```

### Working with Multiple Projects

```ruby
# Project A
model_a = CovLoupe::CoverageModel.new(
  root: '/path/to/projects/service-a',
  coverage_file: '/path/to/projects/service-a/coverage/coverage.json'
)

# Project B
model_b = CovLoupe::CoverageModel.new(
  root: '/path/to/projects/service-b',
  coverage_file: '/path/to/projects/service-b/tmp/coverage/coverage.json'
)

# Compare coverage
coverage_a = model_a.list
coverage_b = model_b.list
```




---

## Error Handling Strategies

### Context-Aware Error Handling

**CLI Mode:** user-facing messages, exit codes, optional debug mode

**Library Mode:** typed exceptions with full details

**MCP Server Mode:** argument-validation and tool-execution failures return a `tools/call` result with `isError: true` (execution failures are logged to the configured log target, `stderr` by default); JSON-RPC errors are reserved for protocol- or dispatch-level failures such as malformed JSON-RPC requests, unknown methods, and unknown tools

### Error Modes

**CLI Error Modes:**
```sh
# No error logging (the error message is still printed)
clp --error-mode off summary app/models/order.rb

# Standard mode (the default) - user-friendly errors, also logged when --log-file names a file
clp --error-mode log summary app/models/order.rb

# Verbose mode - stack traces (only the first 5 lines on stderr when --log-file names a file,
# which gets the full trace)
clp --error-mode debug summary app/models/order.rb
```

**Ruby API Error Handling:**
```ruby
require 'cov_loupe'

begin
  model = CovLoupe::CoverageModel.new(
    root: '/path/to/project',
    coverage_file: '/nonexistent/coverage.json'
  )
rescue CovLoupe::FileError => e
  # Handle missing coverage file
  puts "Coverage file not found: #{e.message}"
rescue CovLoupe::CoverageDataError => e
  # Handle corrupt/invalid coverage data
  puts "Invalid coverage data: #{e.message}"
end
```

### Running the CLI from Ruby

To run the CLI from Ruby, call `CovLoupe.run` with the same arguments you would pass on the
command line. Control error logging and stack traces with `--error-mode` and `--log-file`
in those arguments or in `COV_LOUPE_OPTS`. `CovLoupe.run` may call `exit`. Unlike the
`cov-loupe` executable, it does not install `INT`/`TERM` handlers, check the Ruby version,
treat `-v`/`--version` anywhere in the arguments as a version request (as a global option,
before any subcommand, it still prints the version), or set
`Encoding.default_external` to UTF-8 under the C locale (see
[Library API](LIBRARY_API.md#quick-start) for why that matters for non-ASCII paths).

```ruby
CovLoupe.run(%w[--error-mode debug --log-file cov_loupe.log list])
```

`CovLoupe::CoverageCLI` is internal, and the error handler protocol (`handle_error` and
`convert_standard_error`) is not public API, so a handler class you write may stop working
in any release. See [Public API and Versioning](LIBRARY_API.md#public-api-and-versioning). To act on
errors in your own code, use the library API and rescue the
[exception types](LIBRARY_API.md#exception-types).

---

## Custom Ruby Integration

### Building Custom Coverage Policies

Use the `validate` subcommand to enforce custom coverage policies in CI/CD.
Example predicates are in [`examples/success_predicates/`](../../examples/success_predicates/README.md).

The predicate can be any Ruby object that responds to `call` and accepts a `CoverageModel`
as its argument. This is usually a lambda (proc), but it can also be a nonlambda proc, a class,
or an instance with a `call` method. The predicate should return a truthy value for success 
or `false`/`nil` for failure.

> **⚠️ SECURITY WARNING**
>
> Validation predicates execute as **arbitrary Ruby code with full system privileges**. They have unrestricted access to:
> - File system operations (read, write, delete)
> - Network operations (HTTP requests, sockets)
> - System commands (via backticks, `system()`, `exec()`, etc.)
> - Environment variables and sensitive data
>
> **Only use predicate files from trusted sources.** Treat them like any other executable code in your project.
> - Never use predicates from untrusted or unknown sources
> - Review predicates before use, especially in CI/CD environments
> - Store predicates in version control with code review
> - Be cautious when copying examples from the internet

**Quick Usage:**
```sh
# validate prints no result (only what the predicate itself prints); check the exit code
# with `echo $?` (0 = pass, 3 = fail, 4 = error in the predicate)

# Every file in the coverage data must be >= 80%
clp validate examples/success_predicates/all_files_above_threshold_predicate.rb

# Total project coverage >= 85%
clp validate examples/success_predicates/project_coverage_minimum_predicate.rb

# Custom predicate from file
clp validate coverage_policy.rb

# Inline string mode
clp validate -i '->(m) { m.list["files"].all? { |f| f["percentage"].nil? || f["percentage"] >= 80 } }'
```

**Creating a predicate:**
```ruby
# coverage_policy.rb
->(model) do
  # All files must have >= 80% coverage
  model.list['files'].all? { |f| f['percentage'].nil? || f['percentage'] >= 80 }
end
```

**Advanced predicate with reporting:**

```ruby
# coverage_policy.rb
class CoveragePolicy
  def call(model)
    threshold = 80
    low_files = model.list['files'].select { |f| f['percentage'] && f['percentage'] < threshold }

    if low_files.empty?
      warn "✓ All files have >= #{threshold}% coverage"
      true
    else
      warn "✗ Files below #{threshold}%:"
      low_files.each { |f| warn "  #{f['file']}: #{f['percentage']}%" }
      false
    end
  end
end

CoveragePolicy.new
```

**Exit codes:** `0` pass, `3` predicate returned falsy (validation failed), `4` error in the predicate itself. See the full list under [Exit Codes](CLI_USAGE.md#exit-codes).

See [examples/success_predicates/README.md](../../examples/success_predicates/README.md) for more examples.

### Absolute Paths

Library results report file paths relative to the project root, as the CLI and MCP server do. Files outside the root keep their absolute paths. Expand a path against `model.root` when you need an absolute one:

```ruby
model = CovLoupe::CoverageModel.new(root: '/path/to/project')

data = model.summary_for('app/models/order.rb')
# => { 'schema_version' => 1, 'file' => 'app/models/order.rb', ... }

File.expand_path(data['file'], model.root)
# => "/path/to/project/app/models/order.rb"
```

---

## CI/CD Integration

The CLI is designed for CI/CD use with features that integrate naturally into pipeline workflows:

### Key Integration Features

- **Exit codes**: Non-zero on failure, making it suitable for pipeline failure conditions
- **JSON output**: `-fJ` format for parsing by CI tools and custom processing
- **Staleness checking**: `--raise-on-stale true` to fail on outdated coverage data
- **Validation predicates**: Custom Ruby policies for coverage enforcement

### Basic CI Pattern

```bash
# 1. Run tests to generate coverage
bundle exec rspec

# 2. Validate coverage freshness (fails with exit code 1 if any tracked file is stale
#    or missing from coverage; on the demo fixture it fails, since two lib files are missing)
clp -S true -g "lib/**/*.rb"

# 3. Export data for CI artifacts or further processing
clp -fJ list > coverage-report.json
```

### Using Coverage Validation

Enforce custom coverage policies with the `validate` subcommand:

```bash
# Run tests
bundle exec rspec

# Apply coverage policy (fails with exit code 3 if predicate returns false)
clp validate coverage_policy.rb
```

Exit codes:

- `0` - Success (coverage meets requirements)
- `1` - Runtime error (e.g., missing or stale coverage data with `--raise-on-stale true`)
- `2` - Usage error (invalid options or arguments)
- `3` - Validation failed (coverage policy not met)
- `4` - Predicate error (invalid predicate or an error raised by its own code; coverage-data errors it triggers exit 1)

### Platform-Specific Examples

For platform-specific integration examples (GitHub Actions, GitLab CI, Jenkins, CircleCI, etc.), see community contributions in the [GitHub Discussions](https://github.com/keithrbennett/cov-loupe/discussions).

---

## Advanced Filtering & Glob Patterns {#advanced-filtering-glob-patterns}

### Tracked Globs Overview

**Default behavior:** By default, `--tracked-globs` is empty (`[]`), which means all files in the coverage file are shown. This ensures transparency—you see exactly what SimpleCov measured without any filtering.

**Why opt-in filtering?**

- **Coverage results are not hidden** - Results are not excluded because their filespecs did not match default tracked globs
- **Meaningful validation** - `missing_tracked_files` only flags files you explicitly expect to have coverage
- **Project flexibility** - Different projects use different directory structures

**Important:** Files never loaded during tests appear in the coverage file only if SimpleCov's `cover` globs include them (SimpleCov then records them at 0%). Otherwise they won't be visible with the default empty array; to detect them, set `--tracked-globs` to match the files you expect to have coverage.

**Two purposes of tracked globs:**

1. **Exclude unwanted results** - Only show files from the coverage file that match the patterns
2. **Include files with or without coverage** - Report files that match the patterns but aren't in the coverage file (reported in `missing_tracked_files` for `list`, `missing_from_coverage` for `totals`)

**Best practice:** Set `COV_LOUPE_OPTS` to match your SimpleCov `cover` globs so `list`, `totals`, and missing-file reports use the same scope. See [`--tracked-globs`](CLI_USAGE.md#tracked-globs) for the canonical setup example.

### Pattern Syntax

Uses Ruby's `File.fnmatch` with extended glob support:

```sh
# Single directory, recursive
-g "lib/**/*.rb"

# Multiple patterns (comma-separated; a repeated -g replaces the earlier one)
-g "lib/payments/**/*.rb,lib/ops/jobs/**/*.rb"

# Exclude patterns (use CLI filtering to exclude ops jobs)
clp -fJ list | jq '.files[] | select(.file | test("ops") | not)'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].reject { |f| f["file"].include?("ops") }.each do |f|
    puts JSON.pretty_generate(f)
  end
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ 'self["files"].reject { |f| f["file"].include?("ops") }'

# Complex patterns
-g "app/models/**/*.rb,app/controllers/**/*.rb"
-g "app/**/concerns/*.rb"
```

**Note:** The CLI splits `--tracked-globs` on every comma, including commas inside braces, so a brace pattern such as `lib/{models,controllers}/**/*.rb` breaks into two invalid globs that match nothing. On the CLI, list the alternatives separately (`-g "lib/models/**/*.rb,lib/controllers/**/*.rb"`). The Ruby API and MCP `tracked_globs` take arrays, so brace patterns work there.

### Use Cases

**1. Monitor Subsystem Coverage:**
```sh
# API layer only
clp -g "lib/api/**/*.rb" list

# Core business logic
clp -g "lib/domain/**/*.rb" list
```

**2. Ensure New Files Have Coverage:**
```sh
# Fail if any tracked file lacks coverage
clp -S true -g "lib/features/**/*.rb"
```

**3. Multi-tier Reporting:**
```sh
# Generate separate reports per layer
for layer in models views controllers; do
  clp -g "app/${layer}/**/*.rb" -fJ list > "coverage-${layer}.json"
done
```

### Ruby API with Globs

```ruby
model = CovLoupe::CoverageModel.new

# Filter files in output
api_files = model.list(
  tracked_globs: ['lib/api/**/*.rb']
)['files']

# Multi-pattern filtering
core_files = model.list(
  tracked_globs: [
    'lib/core/**/*.rb',
    'lib/domain/**/*.rb'
  ]
)['files']

# Validate specific subsystems
begin
  model.list(
    raise_on_stale: true,
    tracked_globs: ['lib/critical/**/*.rb']
  )
rescue CovLoupe::CoverageDataProjectStaleError => e
  # Handle missing coverage for critical files
  puts "Critical files missing coverage:"
  e.missing_files.each { |f| puts "  - #{f}" }
end
```

