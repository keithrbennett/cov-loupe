# V4.0 Breaking Changes Guide

[Back to main README](../../index.md)

This document describes the breaking changes introduced in version 4.0.0. These changes affect the CLI flags for mode selection and staleness checks, as well as a method rename in the Ruby API.

## Table of Contents

- [CLI Changes](#cli-changes)
    - [MCP Mode Now Requires Explicit `-m/--mode mcp` Flag](#mcp-mode-now-requires-explicit-m-mode-mcp-flag)
    - [Unified Stale Coverage Enforcement](#unified-stale-coverage-enforcement)
    - [`--raise-on-stale` / `-S` - Explicit Value Required](#raise-on-stale-s-explicit-value-required)
    - [`--color` / `-C` - Explicit Value Required](#color-c-explicit-value-required)
    - [`--tracked-globs` Default Changed to Empty Array](#tracked-globs-default-changed-to-empty-array)
- [Ruby API Changes](#ruby-api-changes)
    - [CoverageLineResolver Now Requires `root:` and `volume_case_sensitive:`](#coveragelineresolver-now-requires-root-and-volume_case_sensitive)
    - [Method Renamed](#method-renamed)
    - [Return Type Changed: `list` Now Returns a Hash](#return-type-changed-list-now-returns-a-hash)
    - [Return Type Changed: `project_totals` Schema Updated](#return-type-changed-project_totals-schema-updated)
    - [Logger Initialization Changed](#logger-initialization-changed)
- [Deleted Files Now Raise `FileNotFoundError`](#deleted-files-now-raise-filenotfounderror)
- [Staleness Indicators Changed to Readable Strings](#staleness-indicators-changed-to-readable-strings)
- [Removed Branch-Only Coverage Support](#removed-branch-only-coverage-support)
- [Getting Help](#getting-help)

---

## CLI Changes

### ⚠️ MCP Mode Now Requires Explicit `-m/--mode mcp` Flag {#mcp-mode-now-requires-explicit-m-mode-mcp-flag}

**BREAKING**: Automatic mode detection has been removed. 
The `-m/--mode mcp` flag is now **required** to run cov-loupe as an MCP server.

#### Previous Behavior (v3.x)
- cov-loupe automatically detected MCP mode based on TTY/stdin status
- `--force-mode` could override detection (values: `cli`, `mcp`, `auto`)

#### New Behavior (v4.x)
- **No automatic detection** - mode defaults to `cli`
- `-m mcp` or `--mode mcp` is **required** for MCP server mode
- Accepted values: `cli` (default) or `mcp`

#### Migration for MCP Users

**If you use cov-loupe as an MCP server, you MUST update your configuration:**

1. **Remove the old entry** (see [MCP Integration Guide - Setup by Client](../MCP_INTEGRATION.md#setup-by-client)
for removal commands with proper `--scope` options)
2. **Add the new entry with `-m mcp` flag:**

```sh
# Claude Code
claude mcp add cov-loupe cov-loupe -- -m mcp

# Codex
codex mcp add cov-loupe cov-loupe -m mcp

# Gemini
gemini mcp add cov-loupe cov-loupe -- -m mcp
```

**Without `-m mcp` or `--mode mcp`, the server will run in CLI mode and hang waiting for subcommands.**

#### Migration for CLI Users

CLI users are unaffected. The default mode is `cli`, so no changes are needed. However:
- `--force-cli` removed → use `-m cli` or `--mode cli` if you need to be explicit (rare)
- `--force-mode` removed → use `-m/--mode` instead

### Unified Stale Coverage Enforcement

The staleness checking logic has been unified into a single flag that raises an error if *any* staleness is detected.

*   **Old**: `--staleness` / `check_stale` (inconsistent behavior)
*   **New**: `--raise-on-stale` (boolean)

#### Behavior
*   **`--raise-on-stale true` (or `raise_on_stale: true`)**: The command will exit with an error code if any file in the result set is stale or if the project totals are stale.
*   **Default (false)**: Staleness is reported in the output (e.g., status `"missing"`, `"newer"`, or `"length_mismatch"`), but the command returns success (unless other errors occur).

#### Migration
*   If you relied on previous flags to enforce staleness checks, switch to `--raise-on-stale true` or `-S true`.

**IMPORTANT:** As of v4.0.0, boolean flags now require explicit values for consistency.

### `--raise-on-stale` / `-S` - Explicit Value Required {#raise-on-stale-s-explicit-value-required}
*   **Old (no longer works)**: `--raise-on-stale`, `-S`
*   **New (required)**: `--raise-on-stale true`, `-S true`, `--raise-on-stale=yes`, etc.

### `--color` / `-C` - Explicit Value Required {#color-c-explicit-value-required}
*   **Old (no longer works)**: `--color`, `-C`
*   **New (required)**: `--color true`, `-C true`, `--color=on`, etc.

These changes improve consistency between short and long flag forms and eliminate ambiguous behavior where long-form bare flags would fail but short-form bare flags would succeed.

### ⚠️ --tracked-globs Default Changed to Empty Array {#tracked-globs-default-changed-to-empty-array}

**BREAKING**: The `--tracked-globs` CLI option now defaults to `[]` (empty) instead of `lib/**/*.rb,app/**/*.rb,src/**/*.rb`. The Ruby API (`CoverageModel`) now also defaults `tracked_globs:` to `[]` (previously `nil`, which behaved the same).

This affects:
- **CLI**: `cov-loupe list` (without `--tracked-globs`)
- **Ruby API**: `CoverageModel.new` (for consistency, though behavior is unchanged)

#### Previous Behavior (v4.x early versions)
- `--tracked-globs` CLI option defaulted to `lib/**/*.rb,app/**/*.rb,src/**/*.rb`
- Files outside these patterns were silently excluded from CLI output
- `missing_tracked_files` (in `list`) included any tracked files not in coverage

#### New Behavior (v4.x current)
- `--tracked-globs` defaults to `[]` (empty)
- Shows all files in the resultset without filtering
- No files are flagged as missing unless you explicitly set globs

#### Rationale

The previous default caused three problems:
1. **Silent exclusions**: Coverage results for files not matching the default patterns (e.g., `config/`, custom directories) were hidden
2. **False positives**: Files like migrations, bin scripts, etc. were incorrectly flagged as "missing"
3. **Wrong assumptions**: Not all projects use `lib/` and `app/` - some use `src/`, others have custom structures

The new default shows all coverage data transparently without making assumptions about your project structure.

#### Migration Steps

**For CLI usage** (if you want the old filtering behavior with `lib/**/*.rb,app/**/*.rb,src/**/*.rb`):

Set `COV_LOUPE_OPTS` to match your SimpleCov `track_files` configuration:

```ruby
# In spec_helper.rb or similar
SimpleCov.start do
  add_filter '/spec/'
  track_files 'lib/**/*.rb'
  track_files 'app/**/*.rb'
end
```

```sh
# In your shell config (.bashrc, .zshrc, etc.)
export COV_LOUPE_OPTS="--tracked-globs lib/**/*.rb,app/**/*.rb"
```

**For Ruby API usage**:

No functional changes needed, but the default signature has changed for consistency. The Ruby API now defaults `tracked_globs: []` (previously `nil`). Both behave identically, so existing code works unchanged:

```ruby
# Default behavior (behavior unchanged, signature updated for consistency)
model = CovLoupe::CoverageModel.new(root: '.')
result = model.list  # tracked_globs: [] → no filtering

# Explicit globs for filtering and tracking
model = CovLoupe::CoverageModel.new(
  root: '.',
  tracked_globs: ['lib/**/*.rb', 'app/**/*.rb']
)
result = model.list  # Uses explicit globs
```

**If you're fine with seeing all files in the resultset (and _only_ files in the resultset)** (no action needed for CLI or Ruby API):
- The new default shows all files that have coverage data
- No filtering applied, but also no detection of files lacking coverage data

#### Important Note

**Files lacking any coverage at all** (not loaded during tests) will not appear in the resultset and therefore won't be visible with the default empty array. To detect such files, you must set `--tracked-globs` to match the files you expect to have coverage.

[↑ Back to top](#table-of-contents)

## Ruby API Changes

### CoverageLineResolver Now Requires `root:` and `volume_case_sensitive:` {#coveragelineresolver-now-requires-root-and-volume_case_sensitive}

**Breaking Change**: `CovLoupe::Resolvers::CoverageLineResolver` now requires `root:` and `volume_case_sensitive:` keyword arguments, and `CovLoupe::Resolvers::ResolverHelpers.lookup_lines` / `create_coverage_resolver` now require these parameters as well.

#### Migration
```ruby
# Old
resolver = CovLoupe::Resolvers::CoverageLineResolver.new(cov_data)
lines = CovLoupe::Resolvers::ResolverHelpers.lookup_lines(cov_data, abs_path)

# New
root = '/path/to/project'
volume_case_sensitive = CovLoupe::PathUtils.volume_case_sensitive?(root)
resolver = CovLoupe::Resolvers::CoverageLineResolver.new(cov_data, root: root, volume_case_sensitive: volume_case_sensitive)
lines = CovLoupe::Resolvers::ResolverHelpers.lookup_lines(cov_data, abs_path, root: root, volume_case_sensitive: volume_case_sensitive)
```

**Note**: If you're using `CoverageModel` (recommended), this is handled automatically - the model detects volume case-sensitivity during initialization based on the project root and passes it to resolvers internally.

### Method Renamed

*   **Old**: `CoverageModel#all_files_coverage`
*   **New**: `CoverageModel#list`

### Return Type Changed: `list` Now Returns a Hash

**Breaking Change**: `CoverageModel#list` now returns a **hash** containing comprehensive staleness information instead of just an array of file data.

#### Old Behavior (v3.x)
```ruby
model = CovLoupe::CoverageModel.new(root: '.')
files = model.list  # Returns array directly

# Filter and use the array
low_coverage = files.select { |f| f['percentage'] < 80 }
model.format_table(files)
```

#### New Behavior (v4.x)
```ruby
model = CovLoupe::CoverageModel.new(root: '.')
result = model.list  # Returns hash with multiple keys

# Access the files array
files = result['files']

# Filter and use the array
low_coverage = files.select { |f| f['percentage'] < 80 }
model.format_table(files)

# Access new staleness information
result['skipped_files']          # Files that raised errors during processing
result['missing_tracked_files']  # Files from tracked_globs not in coverage
result['newer_files']             # Files modified after coverage was generated
result['deleted_files']           # Files in coverage that no longer exist
```

#### Migration Steps

**Option 1: Quick Fix (Extract files array)**
```ruby
# Old
files = model.list

# New
files = model.list['files']
```

**Option 2: Leverage New Staleness Data**
```ruby
result = model.list

# Use the files array as before
files = result['files']
low_coverage = files.select { |f| f['percentage'] < 80 }

# Now you can also:
if result['skipped_files'].any?
  warn "Warning: #{result['skipped_files'].size} files were skipped due to errors"
  result['skipped_files'].each do |skip|
    warn "  #{skip['file']}: #{skip['error']}"
  end
end

if result['newer_files'].any?
  warn "Warning: #{result['newer_files'].size} files are newer than coverage data"
end
```

#### Impact on `format_table`

The `format_table` method still accepts an array of file hashes (not the full hash from `list`):

```ruby
# Correct
files = model.list['files']
table = model.format_table(files)

# Also correct (passing nil gets all files)
table = model.format_table(nil)

# Incorrect - do not pass the full hash
result = model.list
table = model.format_table(result)  # This will fail
```

### Return Type Changed: `project_totals` Schema Updated {#return-type-changed-project_totals-schema-updated}

**Breaking Change**: `CoverageModel#project_totals` now returns a structured hash with
explicit `lines`, `tracking`, and `files` sections. The top-level `percentage` and
`excluded_files` fields were removed.

#### Old Behavior (v3.x)
```ruby
totals = model.project_totals
# => {
#   "lines" => { "total" => 123, "covered" => 100, "uncovered" => 23 },
#   "percentage" => 81.3,
#   "files" => { "total" => 4, "ok" => 4, "stale" => 0 },
#   "excluded_files" => { ... }
# }
```

#### New Behavior (v4.x)
```ruby
totals = model.project_totals
# => {
#   "lines" => {
#     "total" => 123,
#     "covered" => 100,
#     "uncovered" => 23,
#     "percent_covered" => 81.3,
#     "included_files" => 4,
#     "excluded_files" => 0
#   },
#   "tracking" => { "enabled" => true, "globs" => ["lib/**/*.rb"] },
#   "files" => {
#     "total" => 4,
#     "with_coverage" => { "total" => 4, "ok" => 4, "stale" => { "total" => 0, "by_type" => { ... } } }
#   }
# }
```

#### Migration Steps
- Replace `totals['percentage']` with `totals['lines']['percent_covered']`.
- Replace `totals['files']['ok']` and `totals['files']['stale']` with
  `totals['files']['with_coverage']['ok']` and `totals['files']['with_coverage']['stale']['total']`.
- Note the new `lines['included_files']` and `lines['excluded_files']` counts.
- If you relied on `excluded_files`, use `files.with_coverage.stale.by_type` and
  `files.without_coverage.by_type` (present only when tracking is enabled).

### Logger Initialization Changed

The `CovLoupe::Logger` class has updated its `initialize` signature.

*   **Old**: `initialize(target:, mcp_mode: false)`
*   **New**: `initialize(target:, mode: :library)` # or :cli or :mcp

#### Migration

If you are manually instantiating `CovLoupe::Logger`:

```ruby
# Old
logger = CovLoupe::Logger.new(target: 'cov_loupe.log', mcp_mode: true)
logger = CovLoupe::Logger.new(target: 'cov_loupe.log', mcp_mode: false)

# New
logger = CovLoupe::Logger.new(target: 'cov_loupe.log', mode: :mcp)
logger = CovLoupe::Logger.new(target: 'cov_loupe.log', mode: :cli)     # or :library
```

[↑ Back to top](#table-of-contents)

## Deleted Files Now Raise `FileNotFoundError`

**Breaking Change**: Querying a file that has been deleted (but still exists in the coverage resultset) now raises `FileNotFoundError` instead of returning stale coverage data.

### Previous Behavior (v3.x)
```ruby
# File lib/foo.rb was deleted after running tests
model = CovLoupe::CoverageModel.new(root: '.')
result = model.summary_for('lib/foo.rb')
# => { 'file' => '/path/to/lib/foo.rb', 'summary' => { 'covered' => 4, 'total' => 6, 'percentage' => 66.67 } }
# Returns stale coverage data with no error
```

```sh
# CLI would return coverage percentage and exit 0
$ cov-loupe summary lib/foo.rb
lib/foo.rb: 66.67% (4/6)
$ echo $?
0
```

### New Behavior (v4.x)
```ruby
# File lib/foo.rb was deleted after running tests
model = CovLoupe::CoverageModel.new(root: '.')
result = model.summary_for('lib/foo.rb')
# => raises CovLoupe::FileNotFoundError: "File not found: lib/foo.rb"
```

```sh
# CLI raises error and exits 1
$ cov-loupe summary lib/foo.rb
Error: File not found: lib/foo.rb
$ echo $?
1
```

### Rationale

Deleted files represent **stale data** that:
1. Misleads coverage metrics and statistics
2. Violates the API contract (docstring already promised `FileNotFoundError`)
3. Should be treated the same as other staleness issues

If a file no longer exists, its coverage data is no longer meaningful. The new behavior ensures you don't accidentally include deleted file coverage in your metrics.

### Impact

This affects:
- `model.summary_for(path)` - All single-file query methods
- `model.raw_for(path)`
- `model.uncovered_for(path)`
- `model.detailed_for(path)`
- CLI commands: `summary`, `raw`, `uncovered`, `detailed`
- MCP tools: `file_coverage_summary`, `file_coverage_raw`, etc.

### Migration

**If you expect deleted files to raise errors** (recommended):
- No action needed. This is the correct behavior.

**If you relied on getting coverage for deleted files**:
- This was incorrect behavior. Update your workflow to:
  1. Re-run tests after file deletions to get fresh coverage, OR
  2. Use the `list` command to see deleted files in the `deleted_files` array without querying them directly

**Example: Checking for deleted files**
```ruby
model = CovLoupe::CoverageModel.new(root: '.')
result = model.list

if result['deleted_files'].any?
  puts "Warning: Coverage data exists for deleted files:"
  result['deleted_files'].each { |f| puts "  - #{f}" }
end
```

[↑ Back to top](#table-of-contents)

---

## Staleness Indicators Changed to Readable Strings

**Breaking Change**: Staleness indicators in the `stale` field now use readable strings instead of single-character codes.

### Previous Behavior (v3.x)
```ruby
result = model.list
# => { 'files' => [{ 'file' => 'lib/foo.rb', 'stale' => 'M', ... }], ... }

# Staleness was indicated by single-character strings:
# 'M' - Missing file
# 'T' - Timestamp mismatch
# 'L' - Line count mismatch
# 'E' - Error during staleness check
# false - Fresh coverage data
```

### New Behavior (v4.x)
```ruby
result = model.list
# => { 'files' => [{ 'file' => 'lib/foo.rb', 'stale' => "missing", ... }], ... }

# Staleness is now indicated by readable strings:
# "ok" - Fresh coverage data
# "missing" - Missing file
# "newer" - Timestamp mismatch
# "length_mismatch" - Line count mismatch
# "error" - Error during staleness check
```

### Rationale

Readable strings make staleness statuses self-documenting in CLI tables, JSON output, and library code without sacrificing clarity.

### Impact

This affects code that:
- **Checks equality with single-character literals**: `stale == 'M'` will no longer match
- **Uses single-character pattern matching**: Case statements with `'M'`, `'T'`, etc. need updating
- **Checks for `false` to mean fresh**: Fresh files now report `"ok"`

**Frequency**: High - affects any code that checks staleness status.

### Migration

**If you check equality with single-character literals**:
```ruby
# Old
if file['stale'] == 'M'
  puts "File is missing"
end

# New - use readable strings
if file['stale'] == 'missing'
  puts "File is missing"
end
```

**If you use case statements with single-character patterns**:
```ruby
# Old
case file['stale']
when 'M' then handle_missing
when 'T' then handle_timestamp
when 'L' then handle_length
when 'E' then handle_error
when false then handle_fresh
end

# New - use readable strings
case file['stale']
when 'missing' then handle_missing
when 'newer' then handle_timestamp
when 'length_mismatch' then handle_length
when 'error' then handle_error
when 'ok' then handle_fresh
end
```

**If you check for any staleness**:
```ruby
# Old (works for both versions)
if file['stale']
  puts "Stale file (#{file['stale']})"
end

# New - explicit check against "ok"
if file['stale'] != 'ok'
  puts "Stale file (#{file['stale']})"
end
```

**JSON output** uses the same readable strings:
```ruby
# In Ruby
file['stale']  # => "missing"

# In JSON output
{ "file": "lib/foo.rb", "stale": "missing" }
```

**Table output legend updated**:
```
Staleness: missing = Missing file, newer = Timestamp mismatch, length_mismatch = Line count mismatch, error = Check failed
```

### Complete Staleness Value Reference

| Status | v3.x | v4.x | Description |
|--------|------|------|-------------|
| Fresh | `false` | `"ok"` | Coverage data is current |
| Missing file | `'M'` | `"missing"` | File no longer exists on disk |
| Timestamp mismatch | `'T'` | `"newer"` | File modified after coverage was generated |
| Line count mismatch | `'L'` | `"length_mismatch"` | Source file line count differs from coverage data |
| Check error | `'E'` | `"error"` | Staleness check failed (permissions, I/O errors, etc.) |

[↑ Back to top](#table-of-contents)

---

## Removed Branch-Only Coverage Support

**Breaking Change**: The automatic synthesis of line coverage data from SimpleCov branch-only coverage results has been removed.

### Rationale
The logic required to maintain this feature was complex and prone to edge cases, particularly regarding staleness detection and line-count mismatches. Additionally, branch-only coverage is a rarely used configuration in the SimpleCov ecosystem.

### Impact
If your project is configured to track **only** branch coverage in SimpleCov (e.g., `enable_coverage :branch` without also tracking lines), `cov-loupe` will no longer be able to process your coverage data and will raise a `CorruptCoverageDataError`.

### How to Migrate
Most users do not need to take any action. Line coverage is enabled by default in SimpleCov.

If you have `enable_coverage :branch` in your configuration, your `.resultset.json` contains both `lines` and `branches` data. **This is fully supported.** `cov-loupe` will read and report the `lines` coverage as usual.

The change in v4.0 is simply that `cov-loupe` no longer looks at the `branches` data at all. Previously, if `lines` data was missing (a rare edge case), `cov-loupe` would attempt to calculate line coverage by summing up branch hits. This fallback logic has been removed.

[↑ Back to top](#table-of-contents)

---

## Getting Help

If you encounter issues migrating to v4.0:

1.  Check the [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) guide.
2.  Review the [CLI_USAGE.md](../CLI_USAGE.md) for complete CLI reference.
3.  Open an issue at https://github.com/keithrbennett/cov-loupe/issues.
