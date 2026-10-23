# Library API Guide

[Back to main README](../index.md)

Use this gem programmatically to inspect coverage without running the CLI or MCP server. The primary entry point is `CovLoupe::CoverageModel`.

## Table of Contents

- [Public API and Versioning](#public-api-and-versioning)
- [Quick Start](#quick-start)
- [Schema Version](#schema-version)
- [Method Reference](#method-reference)
- [Return Types](#return-types)
- [Error Handling](#error-handling)
- [Advanced Recipes](#advanced-recipes)

## Public API and Versioning

Starting with 7.0, cov-loupe follows [Semantic Versioning](https://semver.org/) for its public API, and only for it:

- **Major** releases may make incompatible changes to it. Each one is described in a [migration guide](migrations/README.md).
- **Minor** releases may add to it: new methods, optional keyword arguments, CLI options, MCP tools or arguments, and payload keys.
- **Patch** releases fix bugs without changing it.

The public API is:

- **Ruby library**: the classes, modules, methods, and constants tagged `@api public` in the source. The tags, not a list in these docs, define it. In outline, it is the `CovLoupe` entry methods (such as `run`, `create_context`, and `with_context`), the classes and modules `CoverageModel`, `CoverageReporter`, `PayloadSchema`, and `ExitCodes`, the [exception classes](#exception-types), and the context objects returned by `create_context`; the tags give the exact members. Of a public method's arguments, only those documented in these guides or in its doc comment are public. To see the tags without reading the source, run `yard doc --api public` for a reference containing only the public API, or browse the gem on [RubyDoc.info](https://www.rubydoc.info/gems/cov-loupe), which marks internal items as part of a private API.
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

- **Human-readable text**: table layouts, the Ruby-rendered output formats (`amazing_print`, `inspect`, `puts`, `pretty_print`), which depend on the Ruby version and other gems, `totals` and other text output, `--help` and `help` tool prose, error message wording, `user_friendly_message` text, log messages, and the string returned by `format_table` or `CoverageReporter.report`. Match on exception classes, exit codes, `isError`, and structured payloads instead.
- **Error handlers**: library calls raise exceptions and never consult the context's configured error handler, so the error handler classes, the `error_handler:` keyword, and the handler protocol (`handle_error`, `convert_standard_error`) are internal. Rescue the [exception types](#exception-types) instead.

## Quick Start

```ruby
require "cov_loupe"

# Defaults (omit args; shown here with comments):
# - root: "."
# - coverage_file: nil (uses coverage/coverage.json under root)
# - raise_on_stale: false (don't raise on stale data)
# - tracked_globs: [] (no project-level file-set checks)
model = CovLoupe::CoverageModel.new

# Custom configuration (non-default values):
model = CovLoupe::CoverageModel.new(
  root: File.join(Dir.home, 'project'),          # non-default project root
  coverage_file: "build/coverage",                # coverage.json file, or its directory
  raise_on_stale: true,                          # enable strict staleness checks (raise on stale)
  tracked_globs: ["lib/cov_loupe/tools/**/*.rb"] # for 'list' staleness: flag new/missing files
)

# List all files with coverage summary
list_result = model.list
# => { 'schema_version' => 1, 'files' => [...], ... }
files = list_result['files']
# Per-file queries

target = 'lib/cov_loupe/base_tool.rb'
summary = model.summary_for(target)
uncovered = model.uncovered_for(target)
detailed = model.detailed_for(target)
raw = model.raw_for(target)
```

Logging is configured through the active context. See the [logging initialization
and target testing guide](LOGGING.md#log-file-initialization-and-target-testing)
for startup probes, lazy file creation, and mode-specific logging failures. In
an explicitly created library-mode context, logging is off by default and an
unusable explicit log target raises `CovLoupe::LoggingError` when the context is
created. The ambient default context is also quiet; CLI and MCP entry points
create their own mode-specific contexts with `stderr` as the default target.

Paths in `coverage.json` are UTF-8. Under the C locale (`LANG=C`), Ruby tags `ARGV`,
`Dir.pwd`, `Dir.glob` and `File.expand_path` results as US-ASCII or BINARY, so non-ASCII
paths, including the ones cov-loupe finds itself under a non-ASCII project root, do not
match. Set `Encoding.default_external = Encoding::UTF_8` before using cov-loupe, as the
`cov-loupe` executable does, and pass non-ASCII paths from `ARGV` as UTF-8. (That also makes
the `:default` output character mode draw Unicode table borders.)

## Schema Version

The hash returned by each public coverage query (`list`, `summary_for`, `uncovered_for`, `detailed_for`, `raw_for`, and `project_totals`) starts with `'schema_version' => CovLoupe::SCHEMA_VERSION`. The value is currently `1`. The key stays with the hash when you serialize it to JSON, YAML, or Marshal. It is independent of the gem's `CovLoupe::VERSION` and of SimpleCov's `schema_version` in the input `coverage.json` file. Methods returning text or status values do not add the key.

The shipped [JSON Schema files](../../lib/cov_loupe/schemas/v1/) define the eight v1 payload shapes: `summary`, `raw`, `uncovered`, `detailed`, `list`, `totals`, `validate_result`, and `help`. Each file uses JSON Schema draft 2020-12. `CovLoupe::PayloadSchema.schema_path('list', version: 1)` returns the installed file path; an unknown name or version raises `ArgumentError`. Library `list` and CLI/MCP project coverage share `list.json`: presentation-only `counts` and `warnings` are optional. The schema IDs use URNs until stable public schema URLs are available.

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

The schema version increments when a key is removed, renamed, or moved, or when a value's type or meaning changes. An incompatible change gets a new `vN` directory copied from the previous version and then edited; earlier version directories are never modified. Adding a key is compatible: add it to the current version's schema file without bumping the version. Consumers must ignore unknown keys so compatible additions remain readable; avoid relying on an exact top-level key set or processing every top-level key as coverage data.

`percentage` always means line coverage: covered lines divided by coverable lines, truncated (not rounded) to two decimals, or `nil` when there are no coverable lines. If other metrics such as branch coverage are added later, they will get their own keys rather than changing what `percentage` means.

Staleness values share one vocabulary across payloads. A per-file `stale` value is one of `"ok"`, `"deleted"`, `"newer"`, `"length_mismatch"`, or `"unreadable"`. The non-`"ok"` values are also the `project_totals` `stale.by_type` keys and match the `list` arrays `deleted_files`, `newer_files`, `length_mismatch_files`, and `unreadable_files`. "Missing" refers only to absent coverage data (`missing_tracked_files`, `missing_from_coverage`) or an absent coverage timestamp (`timestamp_status`).

File paths in payloads (`file` values and the `list` path arrays) are relative to the project root, such as `'lib/foo.rb'`. A file outside the root keeps its absolute path. A relative path whose first directory starts with `~` gets a `./` prefix, so expanding it never resolves to a home directory. Library, CLI, and MCP payloads report the same paths. If you need absolute paths, expand them against the model's root: `File.expand_path(row['file'], model.root)`. `model.root` is the absolute project root, resolved when the model was created.

Paths and glob patterns you pass in (query `path` arguments and `tracked_globs`) follow `File.expand_path` rules, so a leading `~` or `~user` means a home directory. To name a directory under the root whose name starts with `~`, write it as `./~vendor/a.rb`, the form payloads use. Paths cov-loupe reads as data, namely relative `coverage.json` keys and the `file` values of rows passed to `format_table`, always treat a leading `~` as a directory under the root.

## Method Reference

### `list(sort_order: :descending, raise_on_stale: model default, tracked_globs: model default)`

Returns coverage summary for all files in the coverage file.

**Parameters:**
- `sort_order` (Symbol, optional): `:descending` (default) or `:ascending` by coverage percentage
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.
- `tracked_globs` (Array<String>, optional): Patterns to filter files (also used for staleness checks). Defaults to model setting.

**Returns:** `Hash` - See [list return type](#list)

**Example:**
```ruby
list_result = model.list
# => { 'schema_version' => 1, 'files' => [...], ... }
files = list_result['files']
# => [ { 'file' => 'lib/foo.rb', 'covered' => 12, 'total' => 14, 'percentage' => 85.71, 'stale' => "ok" }, ... ]

# Get worst coverage first
worst_files = model.list(sort_order: :ascending)['files'].first(10)

# Force staleness check
model.list(raise_on_stale: true)
```

### `summary_for(path)`

Returns coverage summary for a specific file.

**Parameters:**
- `path` (String): File path (absolute or relative to root)

**Returns:** `Hash` - See [summary_for return type](#summary_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
summary = model.summary_for(target)
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'summary' => {'covered'=>12, 'total'=>14, 'percentage'=>85.71} }
```

**Note:** `CoverageModel#summary_for` returns the schema version, file path, and summary. The CLI and MCP tools add a `stale` field via `CoveragePayloadPresenter`; if you need staleness in library code, call `model.staleness_for(path)` separately.

### `uncovered_for(path)`

Returns list of uncovered line numbers for a specific file.

**Parameters:**
- `path` (String): File path (absolute or relative to root)

**Returns:** `Hash` - See [uncovered_for return type](#uncovered_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
uncovered = model.uncovered_for("lib/foo.rb")
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'uncovered' => [5, 9, 12], 'summary' => { ... } }
```

### `detailed_for(path)`

Returns per-line coverage details with hit counts.

**Parameters:**
- `path` (String): File path (absolute or relative to root)

**Returns:** `Hash` - See [detailed_for return type](#detailed_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
detailed = model.detailed_for("lib/foo.rb")
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'lines' => [{'line' => 1, 'hits' => 1, 'covered' => true}, ...], 'summary' => { ... } }
```

### `raw_for(path)`

Returns raw SimpleCov lines array for a specific file.

**Parameters:**
- `path` (String): File path (absolute or relative to root)

**Returns:** `Hash` - See [raw_for return type](#raw_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
raw = model.raw_for("lib/foo.rb")
# => { 'schema_version' => 1, 'file' => 'lib/foo.rb', 'lines' => [nil, 1, 0, 3, ...] }
```

### `format_table(rows = nil, sort_order: :descending, raise_on_stale: model default, tracked_globs: model default, output_chars: :default)`

Generates a formatted table string.

**Parameters:**
- `rows` (Array<Hash>, optional): Custom row data, such as `list['files']`; `file` values may be relative to the project root or absolute. Defaults to `list`
- `sort_order` (Symbol, optional): `:descending` (default) or `:ascending`
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.
- `tracked_globs` (Array<String>, optional): Patterns to filter files. Defaults to model setting.
- `output_chars` (Symbol, optional): Character mode for table borders and symbols (`:default`, `:fancy`, or `:ascii`).

**Returns:** `String` - Formatted table with Unicode box-drawing borders, or ASCII borders in `:ascii` mode (`:default` chooses by the output encoding). File paths are shown as they are in every mode.

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

### `project_totals(tracked_globs: model default, raise_on_stale: model default)`

Returns aggregated coverage totals across all files.

**Parameters:**
- `tracked_globs` (Array<String> or String, optional): Glob patterns to filter files. Defaults to model setting.
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.

**Returns:** `Hash` - See [project_totals return type](#project_totals)

**Example:**
```ruby
totals = model.project_totals
# => {
#      'schema_version' => 1,
#      'lines' => { 'total' => 123, 'covered' => 100, 'uncovered' => 23, 'percentage' => 81.3 },
#      'tracking' => { 'enabled' => true, 'globs' => ['lib/**/*.rb'] },
#      'files' => { 'total' => 4, 'with_coverage' => { 'total' => 4, 'ok' => 4, 'stale' => { ... } } }
#    }

# Filter to specific directory
lib_totals = model.project_totals(tracked_globs: 'lib/**/*.rb')
```

When `raise_on_stale: true` is set, the method raises on stale coverage instead of returning totals. Otherwise, totals exclude stale files (with staleness indicators `"deleted"`, `"newer"`, `"length_mismatch"`, `"unreadable"`) from line counts and report stale breakdowns under `files['with_coverage']['stale']`.

Note: The `without_coverage` hash will only be present if `tracked_globs` were specified.

### `staleness_for(path)`

Returns the staleness of one file without raising.

**Parameters:**
- `path` (String): File path (absolute or relative to root)

**Returns:** `String` - One of `"ok"`, `"deleted"`, `"newer"`, `"length_mismatch"`, or `"unreadable"`. `"unreadable"` also covers a check that could not be completed, including for a path with no coverage entry; this method does not raise `CovLoupe::FileError`.

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
      'total' => Integer,     # Total relevant lines
      'percentage' => Float | nil, # Line coverage percentage (0.00-100.00); nil if no coverable lines
      'stale' => String       # Staleness indicator: "ok", "deleted", "newer", "length_mismatch", or "unreadable"
    }
  ],
  'skipped_files' => Array<Hash>,          # Skipped rows; each hash has 'file', 'error', 'error_class'
  'missing_tracked_files' => Array<String>,# Tracked files missing from coverage
  'newer_files' => Array<String>,          # Files newer than coverage
  'deleted_files' => Array<String>,        # Coverage entries for deleted files
  'length_mismatch_files' => Array<String>,# Files whose line counts differ from coverage
  'unreadable_files' => Array<String>,     # Files that could not be read
  'timestamp_status' => String             # 'ok' or 'missing'
}
```

### `summary_for` {#summary_for}

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,       # Project-relative path (absolute if outside the root)
  'summary' => {
    'covered' => Integer, # Number of covered lines
    'total' => Integer,   # Total relevant lines
    'percentage' => Float | nil # Line coverage percentage (0.00-100.00); nil if no coverable lines
  }
}
```

The CLI and MCP responses add a `'stale'` field with values `"ok"`, `"deleted"`, `"newer"`, `"length_mismatch"`, or `"unreadable"`.

### `uncovered_for` {#uncovered_for}

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,       # Project-relative path (absolute if outside the root)
  'uncovered' => Array<Integer>,  # Line numbers that are not covered
  'summary' => {
    'covered' => Integer,
    'total' => Integer,
    'percentage' => Float | nil
  }
}
```

### `detailed_for` {#detailed_for}

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,       # Project-relative path (absolute if outside the root)
  'lines' => Array<Hash>, # Per-line coverage details
  'summary' => {
    'covered' => Integer,
    'total' => Integer,
    'percentage' => Float | nil
  }
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

### `raw_for` {#raw_for}

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'file' => String,              # Project-relative path (absolute if outside the root)
  'lines' => Array<Integer | nil>   # SimpleCov lines array (nil = irrelevant, 0 = uncovered, >0 = hit count)
}
```

### `project_totals` {#project_totals}

Returns `Hash`:

```ruby
{
  'schema_version' => Integer, # Currently 1; first top-level key
  'lines' => {
    'total' => Integer,            # Total relevant lines across all files
    'covered' => Integer,          # Total covered lines
    'uncovered' => Integer,        # Total uncovered lines
    'percentage' => Float | nil,   # Overall line coverage percent; nil if no measurable lines
    'included_files' => Integer,   # Non-stale files included in line totals
    'excluded_files' => Integer    # Stale files excluded from line totals
  },
  'tracking' => {
    'enabled' => Boolean,          # Whether tracked_globs are active
    'globs' => Array<String>       # Active tracked globs (empty when disabled)
  },
  'files' => {
    'total' => Integer,          # Total number of files (with + without coverage)
    'with_coverage' => {
      'total' => Integer,        # Files with coverage entries
      'ok' => Integer,           # Fresh coverage entries
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
      'total' => Integer,        # Tracked files missing coverage entries
      'by_type' => {
        'missing_from_coverage' => Integer,
        'unreadable' => Integer,
        'skipped' => Integer
      }
    }
  },
  'timestamp_status' => String   # 'ok' or 'missing'
}
```

Note: The `without_coverage` hash will only be present if `tracked_globs` were specified.

## Error Handling

### Exception Types

All cov-loupe exceptions inherit from `CovLoupe::Error`, which provides `user_friendly_message` and `original_error`. Rescue a parent class to handle all of its subclasses, and list a subclass before its parent when rescuing both.

- **`CovLoupe::Error`** - Base class
  - **`ConfigurationError`** - Invalid configuration
    - **`LoggingError`** - Unusable log target; `#target` names it
  - **`UsageError`** - Invalid command-line usage
  - **`PredicateError`** - A `validate` predicate could not be loaded or raised an error
  - **`UnknownError`** - An unexpected error that fits no other class
  - **`FileError`** - Requested file not in coverage data, or another file or path problem
    - **`FileNotFoundError`** - File does not exist
    - **`FilePermissionError`** - Permission denied
    - **`NotAFileError`** - Path is a directory, not a file
    - **`CoverageFileNotFoundError`** - `coverage.json` not found
  - **`CoverageDataError`** - Coverage data cannot be used: invalid JSON, an unsupported `meta.schema_version`, or a bad structure
    - **`CorruptCoverageDataError`** - A file's coverage entry has no usable `lines` array
    - **`CoverageDataStaleError`** - A file's coverage is stale (only with `raise_on_stale: true`)
    - **`CoverageDataProjectStaleError`** - Project coverage is stale (only with `raise_on_stale: true`)

### Basic Error Handling

```ruby
require "cov_loupe"

begin
  model = CovLoupe::CoverageModel.new
  summary = model.summary_for("lib/foo.rb")
  percentage = summary['summary']['percentage']
  puts "Coverage: #{percentage ? "#{percentage}%" : 'n/a'}"
rescue CovLoupe::CoverageFileNotFoundError => e # subclass of FileError, so rescue it first
  puts "Coverage data not found: #{e.message}"
  puts "Run your tests first: bundle exec rspec"
rescue CovLoupe::FileError => e
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
rescue CovLoupe::CoverageDataStaleError => e
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
    rescue CovLoupe::FileError
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
  percentage = summary['summary']['percentage']
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

# Analyze multiple files efficiently
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
      coverage: summary['summary']['percentage'],
      status: summary['summary']['percentage'].nil? || summary['summary']['percentage'] >= 80 ? :ok : :low
    }
  rescue CovLoupe::FileError
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
patterns = %w[lib/cov_loupe/tools/**/*.rb lib/cov_loupe/commands/**/*.rb lib/cov_loupe/presenters/**/*.rb]

directory_stats = patterns.map do |pattern|
  totals = model.project_totals(tracked_globs: pattern)

  {
    directory: pattern,
    files: totals['files']['total'],
    coverage: totals['lines']['percentage']&.round(2),
    covered: totals['lines']['covered'],
    total: totals['lines']['total']
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

class CoverageReporter
  def initialize(model)
    @model = model
  end

  def generate_markdown_report(output_path)
    files = @model.list['files']
    totals = @model.project_totals

    # Overall stats
    overall_percentage = totals['lines']['percentage']
    overall_display = overall_percentage ? "#{overall_percentage}%" : 'n/a'
    total_lines = totals['lines']['total']
    covered_lines = totals['lines']['covered']
    total_files = totals['files']['total']

    # Files below threshold
    threshold = 80.0
    low_coverage = files.select { |file| file['percentage'] && file['percentage'] < threshold }

    # Build low coverage table
    low_coverage_section = if low_coverage.any?
      rows = low_coverage.sort_by { |file| file['percentage'] }.map do |file|
        uncovered = @model.uncovered_for(file['file'])
        missing_count = uncovered['uncovered'].length
        "| #{file['file']} | #{file['percentage']}% | #{missing_count} |"
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
reporter = CoverageReporter.new(model)
reporter.generate_markdown_report("coverage_report.md")
```

### Custom Library Context (Advanced)

By default, `CoverageModel` logs through the active CovLoupe context. When a block of work needs a different log target, create a context and run that work inside `CovLoupe.with_context`.

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
# For most use cases, just configure the global context once
CovLoupe.default_log_file = 'coverage_analysis.log'

# All models automatically use the active global context
model = CovLoupe::CoverageModel.new
```

## Staleness Detection

The `list` method returns a `'stale'` field for each file with one of these values:

- `"ok"` - Coverage data is current
- `"deleted"` - **Deleted**: File no longer exists on disk
- `"newer"` - **Timestamp**: File modified more recently than coverage data
- `"length_mismatch"` - **Length**: Source file line count differs from coverage data
- `"unreadable"` - **Unreadable**: Source file could not be read, or its staleness check failed

**Note:** Per-file methods (`summary_for`, `uncovered_for`, `detailed_for`, `raw_for`) do not include staleness information in their return values. To check staleness for an individual file, call `model.staleness_for(path)`.

When `raise_on_stale: true` is enabled in `CoverageModel.new`, the model will raise `CovLoupe::CoverageDataStaleError` exceptions when stale files are detected during method calls.

## Related Documentation

- [Ruby Library Examples](examples/ruby-library-examples.md) - Practical cookbook-style examples
- [CLI Usage](CLI_USAGE.md) - Command-line interface reference
- [Error Handling](ERROR_HANDLING.md) - Detailed error handling documentation
- [MCP Integration](MCP_INTEGRATION.md) - AI assistant integration
