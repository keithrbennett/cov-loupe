# Library API Guide

[Back to main README](../../README.md)

Use this gem programmatically to inspect coverage without running the CLI or MCP server. The primary entry point is `CovLoupe::CoverageModel`.

## Table of Contents

- [Public API and Versioning](#public-api-and-versioning)
- [Quick Start](#quick-start)
- [Schema Version](#schema-version)
- [Method Reference](#method-reference)
- [Return Types](#return-types)
- [Error Handling](#error-handling)
- [Advanced Recipes](#advanced-recipes)
- [Staleness Detection](#staleness-detection)
- [Related Documentation](#related-documentation)

## Public API and Versioning

Starting with 7.0, cov-loupe follows [Semantic Versioning](https://semver.org/) for its public API, and only for it:

- **Major** releases may make incompatible changes to it. Each one is described in a [migration guide](migrations/README.md).
- **Minor** releases may add to it: new methods, optional keyword arguments, CLI options, MCP tools or arguments, and payload keys.
- **Patch** releases fix bugs without changing it.

The public API is:

- **Ruby library**: the classes, modules, methods, and constants tagged `@api public` in the source. The tags, not a list in these docs, define it.
    - In outline, it is the `CovLoupe` entry methods (such as `run`, `execute`, `create_context`, and `with_context`); the classes and modules `CoverageModel`, `CoverageReporter`, `PayloadSchema`, and `ExitCodes`; the [exception classes](#exception-types); and the context objects returned by `create_context`. The tags give the exact members.
    - Of a public method's arguments, only those documented in these guides or in its doc comment are public.
    - To see the tags without reading the source, either browse the gem on [RubyDoc.info](https://www.rubydoc.info/gems/cov-loupe), which marks internal items as part of a private API, or run `yard doc --api public` from the root of a cov-loupe source checkout and open `doc/index.html`. YARD is not a cov-loupe dependency; install it with `gem install yard`.
- **Structured output**, **CLI**, and **MCP server** behavior, as described below.
- **`validate` predicates**: a predicate is any object responding to `call`; it receives a `CoverageModel` and returns truthy to pass.

Everything else is internal and may change or be removed in any release, including a patch release, without a migration note. That includes anything tagged `@api private` and undocumented arguments of public methods. Internals described in the [architecture notes](../dev/ARCHITECTURE.md), or used in older guides and migration notes, are still internal. Pre-releases of 7.0.0 may still change the public API.

### Structured Output

The shapes of library coverage hashes, structured CLI output (`-f json`, `pretty_json`, and `yaml`), and structured MCP tool payloads are public. They are defined by the [shipped JSON Schemas](#schema-version), together with the meaning of `percentage` and the staleness values described there.

`schema_version` and the gem version move separately:

- `CovLoupe::SCHEMA_VERSION` versions only the payload shapes, and increments on an incompatible change as defined under [Schema Version](#schema-version). Because payloads are public, that also requires a major gem release.
- A compatible change, such as adding a key, changes neither `schema_version` nor the major gem version, and can ship in a minor release.
- A major gem release can leave `schema_version` unchanged when its breaking changes are elsewhere, for example in a CLI option or a Ruby method.
- Each release emits only the current `schema_version`. The schema files for earlier versions remain installed, so `PayloadSchema.schema_path` can locate the schema needed to validate a saved payload.

### CLI

- The `cov-loupe` executable, its subcommands and their single-letter aliases, their positional arguments, and `validate`'s `-i`/`--inline` option.
- The global options documented in [CLI Usage](CLI_USAGE.md#global-options): long and short names, accepted values, and defaults.
- The `COV_LOUPE_OPTS` environment variable and its precedence below command-line arguments.
- [Exit codes](CLI_USAGE.md#exit-codes).

### MCP Server

- Starting the server with `-m mcp` / `--mode mcp`, and the `--allow-code-predicates` gate for `project_validate`.
- The [tool names](MCP_INTEGRATION.md#tool-catalog), and each tool's argument names, types, enum values, and defaults.
- Successful payloads as described under Structured Output, and the split between `isError: true` results and JSON-RPC `error` responses described in [Error Handling](ERROR_HANDLING.md#mcp-server-mode).

### Not Covered

- **Human-readable text**: table layouts; the Ruby-rendered output formats (`amazing_print`, `inspect`, `puts`, `pretty_print`), which depend on the Ruby version and other gems; `totals` and other text output; `--help` and `help` tool prose; error message wording and `user_friendly_message` text; log messages; and the strings returned by `format_table` and `CoverageReporter.report`. Match on exception classes, exit codes, `isError`, and structured payloads instead.
- **Error handlers**: library calls raise exceptions and never consult the context's configured error handler, so the error handler classes, the `error_handler:` keyword, and the handler protocol (`handle_error`, `convert_standard_error`) are internal. Rescue the [exception types](#exception-types) instead.

## Quick Start

```ruby
require "cov_loupe"

# Defaults (omit args; shown here with comments):
# - root: "."
# - coverage_file: nil (uses coverage/coverage.json under root)
# - raise_on_stale: false (don't raise on stale data)
# - file_globs: [] (no project-level file-set checks)
model = CovLoupe::CoverageModel.new

# Custom configuration (non-default values):
model = CovLoupe::CoverageModel.new(
  root: File.join(Dir.home, 'project'),   # non-default project root
  coverage_file: "build/coverage",        # coverage.json file, or its directory
  raise_on_stale: true,                   # enable strict staleness checks (raise on stale)
  file_globs: ["lib/my_app/**/*.rb"]      # for 'list' staleness: flag files not in coverage data
)

# List all files with coverage summary
list_result = model.list
# => { 'schema_version' => 1, 'files' => [...], ... }
files = list_result['files']
# Per-file queries

target = 'lib/my_app/order.rb'
summary = model.summary_for(target)
uncovered = model.uncovered_for(target)
detailed = model.detailed_for(target)
raw = model.raw_for(target)
```

Logging goes through the active context. In library use, logging is off by default, both in
the ambient default context and in a context you create with `create_context`. Giving a
context an unusable log target raises `CovLoupe::LoggingError` when the context is created.
(The CLI and MCP entry points create their own contexts, which log to `stderr` by default.)
See [Log file initialization and target testing](LOGGING.md#log-file-initialization-and-target-testing)
for how targets are probed, when the file is created, and how each mode reports logging failures.

Paths in `coverage.json` are UTF-8. Under the C locale (`LANG=C`), Ruby tags `ARGV`,
`Dir.pwd`, `Dir.glob` and `File.expand_path` results as US-ASCII or BINARY, so non-ASCII
paths, including the ones cov-loupe finds itself under a non-ASCII project root, do not
match. Set `Encoding.default_external = Encoding::UTF_8` before using cov-loupe, as the
`cov-loupe` executable does, and pass non-ASCII paths from `ARGV` as UTF-8. (That also makes
the `:default` output character mode draw Unicode table borders.)

## Schema Version

The hash returned by each public coverage query (`list`, `summary_for`, `uncovered_for`, `detailed_for`, `raw_for`, and `project_totals`) starts with `'schema_version' => CovLoupe::SCHEMA_VERSION`. The value is currently `1`. The key stays with the hash when you serialize it to JSON, YAML, or Marshal. It is independent of the gem's `CovLoupe::VERSION` and of SimpleCov's `schema_version` in the input `coverage.json` file. Methods returning text or status values do not add the key.

The shipped [JSON Schema files](https://github.com/keithrbennett/cov-loupe/tree/main/lib/cov_loupe/schemas/v1) define the eight v1 payload shapes: `summary`, `raw`, `uncovered`, `detailed`, `list`, `totals`, `validate_result`, and `help`. Each file uses JSON Schema draft 2020-12, and the schema IDs use URNs until stable public schema URLs are available. `CovLoupe::PayloadSchema.schema_path('list', version: 1)` returns the installed file path; an unknown name or version raises `ArgumentError`.

Library, CLI, and MCP payloads are the same, except for two optional keys:

- `source`, added to file payloads by the CLI's `--source` option
- `warnings`, added to `list` and `totals` by the MCP tools when `timestamp_status` is `missing` or most files were not found under the project root

For a previously saved JSON result, load the schema matching the result's own version before using its coverage fields. Add `json_schemer` to your application's dependencies for this example:

```ruby
require 'json'
require 'json_schemer'
require 'cov_loupe'

saved = JSON.parse(File.read('saved-coverage.json'))
schema_path = CovLoupe::PayloadSchema.schema_path('list', version: saved.fetch('schema_version'))
schema = JSONSchemer.schema(JSON.parse(File.read(schema_path)))
raise 'Invalid saved coverage payload' unless schema.valid?(saved)

files = saved.fetch('files')
```

**Compatibility rules.** The schema version increments when a key is removed, renamed, or moved, or when a value's type or meaning changes. An incompatible change gets a new `vN` schema directory, copied from the previous version and then edited; earlier version directories are never modified. Adding an optional key is compatible: it goes into the current version's schema file without a version bump.

Consumers must therefore ignore unknown keys at every level, not only the top level, so that compatible additions remain readable. Do not rely on an exact key set, or treat every key as coverage data.

These rules apply from the 7.0.0 release. 7.0 pre-releases reported `schema_version` 1 with earlier payload shapes, so do not rely on payloads saved by a pre-release.

Line metrics have one shape everywhere: `covered`, `uncovered`, `total` (coverable lines), and `percentage`, as top-level keys of the file payloads (`summary_for`, `uncovered_for`, `detailed_for`), of each `list` row, and of `project_totals`. A `summary_for` payload is therefore a `list` row plus `schema_version`. `percentage` always means line coverage: covered lines divided by coverable lines, truncated (not rounded) to two decimals, or `nil` when there are no coverable lines.

If branch or method coverage is added later, it will arrive as optional objects beside the line metrics, named with a `_coverage` suffix (for example `branch_coverage: { covered, uncovered, total, percentage }`), and will be absent, not `null`, when the coverage file has no such data. Per-item data keeps plain plural names for lists of per-item objects or numbers (`branches` beside `lines`, `uncovered_branches` beside `uncovered_lines`), and a `_hits` suffix for a positional array of hit counts (`branch_hits` beside `line_hits`). The existing line metric keys will keep their meaning.

Some names recur at different levels with different values, and are unambiguous within their parent: a file's `covered` count versus `detailed_for` rows' `covered` boolean; the per-file `stale` string versus the `project_totals` `file_counts.with_coverage.stale` object; `total` coverable lines versus `file_counts` file totals; and `skipped_files` rows (objects) versus the other `*_files` path arrays.

Staleness values share one vocabulary across payloads. A per-file `stale` value is one of `"ok"`, `"deleted"`, `"newer"`, `"length_mismatch"`, or `"unreadable"`. The non-`"ok"` values are also the `project_totals` `stale.by_type` keys and match the `list` arrays `deleted_files`, `newer_files`, `length_mismatch_files`, and `unreadable_files`. "Missing" refers only to absent coverage data (the `list` array `not_in_coverage_files`, counted as `not_in_coverage` in `project_totals`) or an absent coverage timestamp (`timestamp_status`).

File paths in payloads (`file` values and the `list` path arrays) are relative to the project root, such as `'lib/foo.rb'`. A file outside the root keeps its absolute path. A relative path whose first directory starts with `~` gets a `./` prefix, so expanding it never resolves to a home directory. Library, CLI, and MCP payloads report the same paths. If you need absolute paths, expand them against the model's root: `File.expand_path(row['file'], model.root)`. `model.root` is the absolute project root, resolved when the model was created.

Paths and glob patterns you pass in (query `path` arguments and `file_globs`) follow `File.expand_path` rules, so a leading `~` or `~user` means a home directory. To name a directory under the root whose name starts with `~`, write it as `./~vendor/a.rb`, the form payloads use. Paths cov-loupe reads as data, namely relative `coverage.json` keys and the `file` values of rows passed to `format_table`, always treat a leading `~` as a directory under the root.

## Method Reference

### `list(sort_order: :descending, raise_on_stale: model default, file_globs: model default)`

Returns coverage summary for all files in the coverage file.

**Parameters:**

- `sort_order` (Symbol, optional): `:descending` (default) or `:ascending` by coverage percentage
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.
- `file_globs` (Array<String> or String, optional): Report only files matching these patterns, and report matching files that have no coverage data in `not_in_coverage_files`; staleness checks are limited to matching files. Defaults to model setting.

**Returns:** `Hash` - See [list return type](#list)

**Raises:** `ArgumentError` if `sort_order` is not `:ascending` or `:descending` (strings are not accepted). This is checked before any staleness check, so it is raised even when `raise_on_stale` would also fail.

**Example:**
```ruby
list_result = model.list
# => { 'schema_version' => 1, 'files' => [...], ... }
files = list_result['files']
# => [ { 'file' => 'lib/foo.rb', 'covered' => 12, 'uncovered' => 2, 'total' => 14, 'percentage' => 85.71, 'stale' => "ok" }, ... ]

# Get worst coverage first
worst_files = model.list(sort_order: :ascending)['files'].first(10)

# Force staleness check
model.list(raise_on_stale: true)
```

### `summary_for(path, raise_on_stale: model default)`

Returns coverage summary for a specific file.

**Parameters:**

- `path` (String): File path (absolute or relative to root)
- `raise_on_stale` (Boolean, optional): Whether to raise `CovLoupe::CoverageDataStaleError` if the file is stale. Defaults to model setting.

**Returns:** `Hash` - See [summary_for return type](#summary_for)

**Raises:** `CovLoupe::CoverageEntryNotFoundError` if file not in coverage data, `CovLoupe::AmbiguousCoverageEntryError` if several coverage entries match it; when `raise_on_stale` is true, `CovLoupe::CoverageDataStaleError` if stale, `CovLoupe::FileNotFoundError` if the file was deleted, and `CovLoupe::FileError` if it is unreadable

**Example:**
```ruby
summary = model.summary_for(target)
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'covered' => 12, 'uncovered' => 2,
#      'total' => 14, 'percentage' => 85.71, 'stale' => 'ok' }
```

Every file query includes the file's `stale` value, as the CLI and MCP tools do. With `raise_on_stale: true` it is always `"ok"`, since a stale file raises instead.

### `uncovered_for(path, raise_on_stale: model default)`

Returns list of uncovered line numbers for a specific file.

**Parameters:**

- `path` (String): File path (absolute or relative to root)
- `raise_on_stale` (Boolean, optional): Whether to raise `CovLoupe::CoverageDataStaleError` if the file is stale. Defaults to model setting.

**Returns:** `Hash` - See [uncovered_for return type](#uncovered_for)

**Raises:** `CovLoupe::CoverageEntryNotFoundError` if file not in coverage data, `CovLoupe::AmbiguousCoverageEntryError` if several coverage entries match it; when `raise_on_stale` is true, `CovLoupe::CoverageDataStaleError` if stale, `CovLoupe::FileNotFoundError` if the file was deleted, and `CovLoupe::FileError` if it is unreadable

**Example:**
```ruby
uncovered = model.uncovered_for("lib/foo.rb")
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'uncovered_lines' => [5, 9, 12],
#      'covered' => 11, 'uncovered' => 3, 'total' => 14, 'percentage' => 78.57, 'stale' => 'ok' }
```

### `detailed_for(path, raise_on_stale: model default)`

Returns per-line coverage details with hit counts.

**Parameters:**

- `path` (String): File path (absolute or relative to root)
- `raise_on_stale` (Boolean, optional): Whether to raise `CovLoupe::CoverageDataStaleError` if the file is stale. Defaults to model setting.

**Returns:** `Hash` - See [detailed_for return type](#detailed_for)

**Raises:** `CovLoupe::CoverageEntryNotFoundError` if file not in coverage data, `CovLoupe::AmbiguousCoverageEntryError` if several coverage entries match it; when `raise_on_stale` is true, `CovLoupe::CoverageDataStaleError` if stale, `CovLoupe::FileNotFoundError` if the file was deleted, and `CovLoupe::FileError` if it is unreadable

**Example:**
```ruby
detailed = model.detailed_for("lib/foo.rb")
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb',
#      'lines' => [{'line' => 1, 'hits' => 1, 'covered' => true}, ...],
#      'covered' => 12, 'uncovered' => 2, 'total' => 14, 'percentage' => 85.71, 'stale' => 'ok' }
```

### `raw_for(path, raise_on_stale: model default)`

Returns SimpleCov's raw per-line hit counts (its `lines` array) for a specific file, as `line_hits`. Lines SimpleCov marked `"ignored"` (excluded with `nocov` blocks or directive comments) are returned as `null` and, like other `null` lines, are not counted in covered or total lines or in percentages.

**Parameters:**

- `path` (String): File path (absolute or relative to root)
- `raise_on_stale` (Boolean, optional): Whether to raise `CovLoupe::CoverageDataStaleError` if the file is stale. Defaults to model setting.

**Returns:** `Hash` - See [raw_for return type](#raw_for)

**Raises:** `CovLoupe::CoverageEntryNotFoundError` if file not in coverage data, `CovLoupe::AmbiguousCoverageEntryError` if several coverage entries match it; when `raise_on_stale` is true, `CovLoupe::CoverageDataStaleError` if stale, `CovLoupe::FileNotFoundError` if the file was deleted, and `CovLoupe::FileError` if it is unreadable

**Example:**
```ruby
raw = model.raw_for("lib/foo.rb")
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'line_hits' => [nil, 1, 0, 3, ...], 'stale' => 'ok' }
```

### `format_table(rows = nil, sort_order: :descending, raise_on_stale: model default, file_globs: model default, output_chars: :default)`

Generates a formatted table string.

**Parameters:**

- `rows` (Array<Hash>, optional): Custom row data, such as `list['files']`; `file` values may be relative to the project root or absolute. Defaults to `list`
- `sort_order` (Symbol, optional): `:descending` (default) or `:ascending`
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting. Used only when `rows` is omitted, since supplied rows are not rechecked.
- `file_globs` (Array<String> or String, optional): Show only rows for files matching these patterns. Defaults to model setting.
- `output_chars` (Symbol, optional): Character mode for table borders and symbols (`:default`, `:fancy`, or `:ascii`).

**Returns:** `String` - Formatted table with Unicode box-drawing borders, or ASCII borders in `:ascii` mode (`:default` chooses by the output encoding). File paths are shown as they are in every mode.

**Raises:** `ArgumentError` if `sort_order` is not `:ascending` or `:descending` (strings are not accepted), checked before any staleness check; or if `output_chars` is not `:default`, `:fancy` or `:ascii` and there are rows to format.

**Example:**
```ruby
# Default: all files
table = model.format_table
puts table

# Custom rows
lib_files = model.list['files'].select { |f| f['file'].start_with?('lib/') }
lib_table = model.format_table(lib_files, sort_order: :descending)
puts lib_table
```

### `project_totals(file_globs: model default, raise_on_stale: model default)`

Returns aggregated coverage totals across all files.

**Parameters:**

- `file_globs` (Array<String> or String, optional): Count only files matching these patterns, and count matching files that have no coverage data under `without_coverage` (`not_in_coverage` is `nil` without them). Defaults to model setting.
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.

**Returns:** `Hash` - See [project_totals return type](#project_totals)

**Example (abbreviated; see the return type for every key):**
```ruby
totals = model.project_totals
# => {
#      'schema_version' => 1,
#      'covered' => 100, 'uncovered' => 23, 'total' => 123, 'percentage' => 81.3,
#      'file_globs' => [],
#      'file_counts' => {
#        'total' => 4,
#        'with_coverage' => { 'total' => 4, 'ok' => 4, 'stale' => { ... } },
#        'without_coverage' => { 'total' => 0, 'by_type' => { 'not_in_coverage' => nil, 'skipped' => 0 } }
#      },
#      'timestamp_status' => 'ok'
#    }

# Filter to specific directory
lib_totals = model.project_totals(file_globs: 'lib/**/*.rb')
```

When `raise_on_stale: true` is set, the method raises on stale coverage instead of returning totals. Otherwise, the line counts exclude stale files (`"deleted"`, `"newer"`, `"length_mismatch"`, `"unreadable"`), and the stale breakdown is reported under `file_counts['with_coverage']['stale']`. `file_counts['with_coverage']['ok']` is the number of files the line counts include.

### `staleness_for(path)`

Returns the staleness of one file.

**Parameters:**

- `path` (String): File path (absolute or relative to root)

**Returns:** `String` - One of `"ok"`, `"deleted"`, `"newer"`, `"length_mismatch"`, or `"unreadable"`. `"unreadable"` means the source file could not be read, or its staleness check failed.

**Raises:** what the file queries raise for the same path: `CovLoupe::CoverageEntryNotFoundError` if the file is not in the coverage data, `CovLoupe::AmbiguousCoverageEntryError` if several coverage entries match it, another `CovLoupe::CoverageDataError` (such as `CorruptCoverageDataError`) if its entry is malformed, and coverage-file errors such as `CovLoupe::CoverageFileNotFoundError`. It never raises for staleness itself.

**Example:**
```ruby
model.staleness_for('lib/foo.rb')
# => "ok"
```

### `coverage_file_path`

Returns the absolute path of the `coverage.json` file the model loaded.

**Returns:** `String`

**Example:**
```ruby
model.coverage_file_path
# => "/path/to/project/coverage/coverage.json"
```

### `root`

Returns the absolute project root, resolved when the model was created. Relative payload paths are relative to it.

**Returns:** `String`

**Example:**
```ruby
model.root
# => "/path/to/project"
File.expand_path(model.summary_for('lib/foo.rb')['file'], model.root)
# => "/path/to/project/lib/foo.rb"
```

### `CoverageReporter.report(threshold: 80, count: 5, model: nil, root: nil, coverage_file: nil)`

Returns a short text report of the lowest-covered files below `threshold`, or `nil` if there are none. A module method on `CovLoupe::CoverageReporter`, meant for a SimpleCov `at_exit` hook; it uses SimpleCov's root and coverage directory when SimpleCov is loaded. See [Test Run Integration](examples/test-run-integration.md) for the parameters and an example.

## Return Types

### `list`

Returns `Hash` with file data and staleness metadata:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'files' => [
    {
      'file' => String,       # Project-relative path (absolute if outside the root)
      'covered' => Integer,   # Number of covered lines
      'uncovered' => Integer, # Number of coverable lines with no hits
      'total' => Integer,     # Number of coverable lines
      'percentage' => Float | nil, # Line coverage percentage (0.00-100.00); nil if no coverable lines
      'stale' => String       # Staleness indicator: "ok", "deleted", "newer", "length_mismatch", or "unreadable"
    }
  ],
  'skipped_files' => Array<Hash>,          # Skipped rows; each hash has 'file', 'error', 'error_class'
  'not_in_coverage_files' => Array<String>,# Files matching the file globs that are not in coverage data
  'newer_files' => Array<String>,          # Files newer than coverage
  'deleted_files' => Array<String>,        # Coverage entries for deleted files
  'length_mismatch_files' => Array<String>,# Files whose line counts differ from coverage
  'unreadable_files' => Array<String>,     # Files that could not be read
  'timestamp_status' => String             # 'ok' or 'missing'
}
```

### `summary_for`

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,       # Project-relative path (absolute if outside the root)
  'covered' => Integer,   # Number of covered lines
  'uncovered' => Integer, # Number of coverable lines with no hits
  'total' => Integer,     # Number of coverable lines
  'percentage' => Float | nil, # Line coverage percentage (0.00-100.00); nil if no coverable lines
  'stale' => String       # "ok", "deleted", "newer", "length_mismatch", or "unreadable"
}
```

This is the same hash as the file's `list` row, plus `schema_version`.

### `uncovered_for`

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,       # Project-relative path (absolute if outside the root)
  'uncovered_lines' => Array<Integer>, # Line numbers that are not covered
  'covered' => Integer,   # Line metrics, as in summary_for
  'uncovered' => Integer, # Count of uncovered_lines
  'total' => Integer,
  'percentage' => Float | nil,
  'stale' => String       # "ok", "deleted", "newer", "length_mismatch", or "unreadable"
}
```

### `detailed_for`

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,       # Project-relative path (absolute if outside the root)
  'lines' => Array<Hash>, # Per-line coverage details
  'covered' => Integer,   # Line metrics, as in summary_for
  'uncovered' => Integer,
  'total' => Integer,
  'percentage' => Float | nil,
  'stale' => String       # "ok", "deleted", "newer", "length_mismatch", or "unreadable"
}
```

Each element in `lines` array:
```ruby
{
  'line' => Integer,    # Line number (1-indexed)
  'hits' => Integer,    # Execution count (0 means not covered)
  'covered' => Boolean  # true if hits > 0
}
```

### `raw_for`

Returns `Hash`:

```ruby
{
  'schema_version' => Integer,           # Currently 1; first top-level key
  'file' => String,                      # Project-relative path (absolute if outside the root)
  'line_hits' => Array<Integer | nil>,   # SimpleCov lines array (nil = not code or ignored, 0 = uncovered, >0 = hit count)
  'stale' => String                      # "ok", "deleted", "newer", "length_mismatch", or "unreadable"
}
```

### `project_totals`

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'covered' => Integer,            # Covered lines in fresh (non-stale) files
  'uncovered' => Integer,          # Uncovered lines in fresh files
  'total' => Integer,              # Coverable lines in fresh files
  'percentage' => Float | nil,     # Overall line coverage percent; nil if no measurable lines
  'file_globs' => Array<String>,   # Active file globs (empty when none were given)
  'file_counts' => {
    'total' => Integer,          # Total number of files (with + without coverage)
    'with_coverage' => {
      'total' => Integer,        # Files with coverage entries (skipped rows excluded)
      'ok' => Integer,           # Fresh coverage entries (the files the line metrics include)
      'stale' => {
        'total' => Integer,      # Stale coverage entries
        'by_type' => {
          'deleted' => Integer,
          'newer' => Integer,
          'length_mismatch' => Integer,
          'unreadable' => Integer
        }
      }
    },
    'without_coverage' => {
      'total' => Integer,        # Files without usable coverage data: sum of the non-nil by_type counts
      'by_type' => {
        'not_in_coverage' => Integer | nil, # Count of the list's not_in_coverage_files; nil without file_globs
        'skipped' => Integer
      }
    }
  },
  'timestamp_status' => String   # 'ok' or 'missing'
}
```

Note: `without_coverage.by_type.not_in_coverage` is `nil` when `file_globs` is empty, since there is then no list of files to check; the other counts are always integers.

## Error Handling

### Exception Types

All public cov-loupe exceptions inherit from `CovLoupe::Error`, which provides `user_friendly_message` and `original_error`. Rescue a parent class to handle all of its subclasses, and list a subclass before its parent when rescuing both.

- **`CovLoupe::Error`** - Base class
    - **`ConfigurationError`** - Invalid configuration
        - **`LoggingError`** - Unusable log target; `#target` names it
    - **`UsageError`** - Invalid command-line usage
    - **`PredicateError`** - A `validate` predicate could not be loaded or raised an error
    - **`UnknownError`** - An unexpected error that fits no other class
    - **`TextEncodingError`** - Text could not be converted between encodings outside coverage loading, such as CLI or MCP output to a stream that transcodes to a non-UTF-8 encoding
    - **`FileError`** - A file or path problem, such as a source file that cannot be read
        - **`FileNotFoundError`** - File does not exist
        - **`FilePermissionError`** - Permission denied
        - **`NotAFileError`** - Path is a directory, not a file
        - **`CoverageFileNotFoundError`** - `coverage.json` not found
    - **`CoverageDataError`** - Coverage data cannot be used: invalid JSON, an unsupported `meta.schema_version`, a bad structure, or no single entry for a requested file
        - **`CoverageEntryNotFoundError`** - The requested file is not in the coverage data
        - **`AmbiguousCoverageEntryError`** - Several coverage entries match the requested path
        - **`CorruptCoverageDataError`** - A file's coverage entry has no usable `lines` array; raised on load when a non-empty coverage map has no entry with one (line coverage disabled)
        - **`CoverageDataStaleError`** - A file's coverage is stale (only with `raise_on_stale: true`)
        - **`CoverageDataProjectStaleError`** - Project coverage is stale (only with `raise_on_stale: true`)

An invalid value for a fixed-choice `CoverageModel` argument is a programming error, not a cov-loupe error: `list` and `format_table` raise Ruby's `ArgumentError` for an invalid `sort_order`, and `format_table` raises it for an invalid `output_chars` when there are rows to format. Rescuing `CovLoupe::Error` does not catch it. Other bad arguments, such as a `coverage_file` that does not exist, raise `CovLoupe::Error` subclasses as listed above.

### Basic Error Handling

```ruby
require "cov_loupe"

begin
  model = CovLoupe::CoverageModel.new
  summary = model.summary_for("lib/foo.rb")
  percentage = summary['percentage']
  puts "Coverage: #{percentage ? "#{percentage}%" : 'n/a'}"
rescue CovLoupe::CoverageFileNotFoundError => e
  puts "Coverage data not found: #{e.message}"
  puts "Run your tests first: bundle exec rspec"
rescue CovLoupe::CoverageEntryNotFoundError => e
  puts "File not in coverage data: #{e.message}"
rescue CovLoupe::Error => e
  puts "Coverage error: #{e.message}"
end
```

### Handling Stale Coverage

```ruby
# Option 1: Check staleness without raising
model = CovLoupe::CoverageModel.new(raise_on_stale: false)
files = model.list['files']

stale_files = files.select { |f| f['stale'] != 'ok' }
if stale_files.any?
  puts "Warning: #{stale_files.length} files have stale coverage"
  stale_files.each do |f|
    puts "  #{f['file']}: #{f['stale']}"
  end
end

# Option 2: Raise on staleness
begin
  model = CovLoupe::CoverageModel.new(raise_on_stale: true)
  files = model.list['files']
rescue CovLoupe::CoverageDataStaleError, CovLoupe::CoverageDataProjectStaleError => e
  puts "Stale coverage detected: #{e.message}"
  puts "Re-run tests: bundle exec rspec"
  exit 1
end
```

### Graceful Degradation

```ruby
# Try multiple file paths
def find_coverage(model, possible_paths)
  possible_paths.each do |path|
    begin
      return model.summary_for(path)
    rescue CovLoupe::CoverageEntryNotFoundError, CovLoupe::AmbiguousCoverageEntryError
      next
    end
  end
  nil
end

summary = find_coverage(model, [
  "lib/services/auth_service.rb",
  "app/services/auth_service.rb",
  "services/auth_service.rb"
])

if summary
  percentage = summary['percentage']
  puts "Coverage: #{percentage ? "#{percentage}%" : 'n/a'}"
else
  puts "File not found in coverage data"
end
```

## Advanced Recipes

### Batch File Analysis

```ruby
require "cov_loupe"

model = CovLoupe::CoverageModel.new

# Check a fixed set of files
files_to_check = [
  "lib/auth_service.rb",
  "lib/payment_processor.rb",
  "lib/user_manager.rb"
]

results = files_to_check.map do |path|
  begin
    summary = model.summary_for(path)
    {
      file: path,
      coverage: summary['percentage'],
      status: summary['percentage'].nil? || summary['percentage'] >= 80 ? :ok : :low
    }
  rescue CovLoupe::CoverageEntryNotFoundError, CovLoupe::AmbiguousCoverageEntryError
    {
      file: path,
      coverage: nil,
      status: :missing
    }
  end
end

# Report
results.each do |r|
  status_icon = { ok: '✓', low: '⚠', missing: '✗' }[r[:status]]
  puts "#{status_icon} #{r[:file]}: #{r[:coverage] ? "#{r[:coverage]}%" : 'n/a'}"
end
```

### Coverage Threshold Validation

```ruby
require "cov_loupe"

class CoverageValidator
  THRESHOLDS = {
    'lib/api/' => 90.0,         # API layer needs 90%+
    'app/models/' => 85.0,      # Models need 85%+
    'app/controllers/' => 75.0, # Controllers need 75%+
  }

  def initialize(model)
    @model = model
  end

  def validate!
    files = @model.list['files']
    failures = []

    files.each do |file|
      threshold = threshold_for(file['file'])
      next unless threshold

      if file['percentage'] && file['percentage'] < threshold
        failures << {
          file: file['file'],
          actual: file['percentage'],
          required: threshold,
          gap: threshold - file['percentage']
        }
      end
    end

    if failures.any?
      puts "❌ #{failures.length} files below coverage threshold:"
      failures.sort_by { |f| -f[:gap] }.each do |f|
        puts "  #{f[:file]}: #{f[:actual]}% (need #{f[:required]}%)"
      end
      exit 1
    else
      puts "✓ All files meet coverage thresholds"
    end
  end

  private

  def threshold_for(path)
    THRESHOLDS.each do |prefix, threshold|
      return threshold if path.include?(prefix)
    end
    nil
  end
end

model = CovLoupe::CoverageModel.new
validator = CoverageValidator.new(model)
validator.validate!
```

### Directory-Level Aggregation

```ruby
require "cov_loupe"

model = CovLoupe::CoverageModel.new

# Calculate coverage by directory using the totals API
patterns = %w[app/models/**/*.rb app/controllers/**/*.rb lib/**/*.rb]

directory_stats = patterns.map do |pattern|
  totals = model.project_totals(file_globs: pattern)

  {
    directory: pattern,
    files: totals['file_counts']['total'],
    coverage: totals['percentage']&.round(2),
    covered: totals['covered'],
    total: totals['total']
  }
end

# Display sorted by coverage (nil, meaning no measurable lines, sorts first)
directory_stats.sort_by { |s| s[:coverage] || -1 }.each do |stat|
  coverage = stat[:coverage] ? "#{stat[:coverage]}%" : 'n/a'
  puts "#{stat[:directory]}: #{coverage} (#{stat[:files]} files)"
end
```

### Coverage Delta Tracking

```ruby
require "cov_loupe"
require "json"

class CoverageDeltaTracker
  def initialize(baseline_path: "coverage_baseline.json")
    @baseline_path = baseline_path
    @model = CovLoupe::CoverageModel.new
  end

  def save_baseline
    current = @model.list['files']
    File.write(@baseline_path, JSON.pretty_generate(current))
    puts "Saved coverage baseline (#{current.length} files)"
  end

  def compare
    unless File.exist?(@baseline_path)
      puts "No baseline found. Run save_baseline first."
      return
    end

    baseline = JSON.parse(File.read(@baseline_path))
    current = @model.list['files']

    improved = []
    regressed = []

    current.each do |file|
      baseline_file = baseline.find { |f| f['file'] == file['file'] }
      next unless baseline_file && file['percentage'] && baseline_file['percentage']

      delta = file['percentage'] - baseline_file['percentage']

      if delta > 0.1
        improved << {
          file: file['file'],
          before: baseline_file['percentage'],
          after: file['percentage'],
          delta: delta
        }
      elsif delta < -0.1
        regressed << {
          file: file['file'],
          before: baseline_file['percentage'],
          after: file['percentage'],
          delta: delta
        }
      end
    end

    if improved.any?
      puts "\n✓ Coverage Improvements:"
      improved.sort_by { |f| -f[:delta] }.each do |f|
        puts "  #{f[:file]}: #{f[:before]}% → #{f[:after]}% (+#{f[:delta].round(2)}%)"
      end
    end

    if regressed.any?
      puts "\n⚠ Coverage Regressions:"
      regressed.sort_by { |f| f[:delta] }.each do |f|
        puts "  #{f[:file]}: #{f[:before]}% → #{f[:after]}% (#{f[:delta].round(2)}%)"
      end
    end

    if improved.empty? && regressed.empty?
      puts "No significant coverage changes"
    end
  end
end

# Usage
tracker = CoverageDeltaTracker.new
tracker.save_baseline  # Run before making changes
# ... make code changes and re-run tests ...
tracker.compare        # See what changed
```

### Custom Reporting

```ruby
require "cov_loupe"

class MarkdownCoverageReport
  def initialize(model)
    @model = model
  end

  def generate_markdown_report(output_path)
    files = @model.list['files']
    totals = @model.project_totals

    # Overall stats
    overall_percentage = totals['percentage']
    overall_display = overall_percentage ? "#{overall_percentage}%" : 'n/a'
    total_lines = totals['total']
    covered_lines = totals['covered']
    total_files = totals['file_counts']['total']

    # Files below threshold
    threshold = 80.0
    low_coverage = files.select { |file| file['percentage'] && file['percentage'] < threshold }

    # Build low coverage table
    low_coverage_section = if low_coverage.any?
      rows = low_coverage.sort_by { |file| file['percentage'] }.map do |file|
        "| #{file['file']} | #{file['percentage']}% | #{file['uncovered']} |"
      end.join("\n")

      <<~LOW_COVERAGE_TABLE

        ## Files Below #{threshold}% Coverage

        | File | Coverage | Missing Lines |
        |------|----------|---------------|
        #{rows}
      LOW_COVERAGE_TABLE
    else
      ""
    end

    # Build top performers table
    top_rows = files.select { |file| file['percentage'] }.sort_by { |file| -file['percentage'] }.take(10).map do |file|
      "| #{file['file']} | #{file['percentage']}% |"
    end.join("\n")

    # Generate report
    report = <<~COVERAGE_REPORT
      # Coverage Report

      Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      ## Overall Coverage: #{overall_display}

      - Total Files: #{total_files}
      - Total Lines: #{total_lines}
      - Covered Lines: #{covered_lines}
      #{low_coverage_section}
      ## Top 10 Best Covered Files

      | File | Coverage |
      |------|----------|
      #{top_rows}
    COVERAGE_REPORT

    File.write(output_path, report)
    puts "Report saved to #{output_path}"
  end
end

model = CovLoupe::CoverageModel.new
reporter = MarkdownCoverageReport.new(model)
reporter.generate_markdown_report("coverage_report.md")
```

### Custom Library Context (Advanced)

By default, `CoverageModel` logs through the CovLoupe context that is active when the model is created; changing the context later does not redirect an existing model. When a block of work needs a different log target, create a context and run that work inside `CovLoupe.with_context`.

```ruby
require "cov_loupe"

# Scenario: Analyzing coverage for multiple projects in one script

# Project A: Detailed logging for debugging
context_a = CovLoupe.create_context(log_target: 'project_a_coverage.log')

summary_a = CovLoupe.with_context(context_a) do
  model_a = CovLoupe::CoverageModel.new(
    root: '/path/to/project_a',
    coverage_file: '/path/to/project_a/coverage/coverage.json'
  )
  model_a.summary_for('lib/foo.rb')
end

# Project B: Different log file
context_b = context_a.with(log_target: 'project_b_coverage.log')

summary_b = CovLoupe.with_context(context_b) do
  model_b = CovLoupe::CoverageModel.new(
    root: '/path/to/project_b',
    coverage_file: '/path/to/project_b/coverage/coverage.json'
  )
  model_b.summary_for('lib/bar.rb')
end
```

**When to use custom contexts:**

- Managing coverage for multiple projects in one script
- Separate log files for different data sources
- Testing scenarios requiring isolated configurations

**Simple use case (most common):**
```ruby
# Usually it is enough to set the process-wide default log target once
CovLoupe.default_log_file = 'coverage_analysis.log'

# Models created afterwards log there
model = CovLoupe::CoverageModel.new
```

## Staleness Detection

The `list` rows and the per-file methods (`summary_for`, `uncovered_for`, `detailed_for`, `raw_for`) return a `'stale'` field with one of these values:

- `"ok"` - Coverage data is current
- `"deleted"` - File no longer exists on disk
- `"newer"` - File modified more recently than coverage data
- `"length_mismatch"` - Source file line count differs from coverage data
- `"unreadable"` - Source file could not be read, or its staleness check failed

When `raise_on_stale: true` is enabled in `CoverageModel.new`, the model raises `CovLoupe::CoverageDataStaleError` from per-file methods and `CovLoupe::CoverageDataProjectStaleError` from project-level methods (`list`, `project_totals`) when stale files are detected. A per-file method raises `CovLoupe::FileNotFoundError` instead for a deleted file and `CovLoupe::FileError` for an unreadable one.

## Related Documentation

- [CLI Usage](CLI_USAGE.md) - Command-line interface reference
- [Error Handling](ERROR_HANDLING.md) - Detailed error handling documentation
- [MCP Integration](MCP_INTEGRATION.md) - AI assistant integration
