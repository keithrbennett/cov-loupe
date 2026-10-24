# V2.0 Breaking Changes and Migration Guide

[Back to main README](../../../README.md)

This document describes all breaking changes introduced in version 2.0.0 of simplecov-mcp. These changes improve consistency, clarity, and alignment with Ruby conventions.

> Note: Current versions use the boolean `--raise-on-stale` / `raise_on_stale` flag (short form `-S`) for staleness enforcement. The `--staleness` and `stale` names referenced below are kept for historical context about the v1→v2 transition.

---

## Table of Contents

- [Command Line Interface Changes](#command-line-interface-changes)
    - [Error Mode Values Changed](#error-mode-values-changed)
    - [Default Sort Order Changed](#default-sort-order-changed)
- [MCP Tool Changes](#mcp-tool-changes)
    - [stale Parameter Renamed to staleness](#stale-parameter-renamed-to-staleness)
    - [MCP Tool Arguments Use Symbols](#mcp-tool-arguments-use-symbols)
- [Ruby API Changes](#ruby-api-changes)
    - [CLIConfig Renamed to AppConfig](#cliconfig-renamed-to-appconfig)
    - [AppConfig Field Changes](#appconfig-field-changes)
- [Behavioral Changes](#behavioral-changes)
    - [Context Lines Validation](#context-lines-validation)
- [Migration Guide](#migration-guide)

---

## Command Line Interface Changes



**Migration:** Move all global options before the subcommand name. These options are:

`-r`, `-R`, `-f`, `-o`, `-s`, `-c`, `-C`, `-S`, `-g`, `-l`, `-F`, `-e`, and `-p`

**Exception:** The `validate` subcommand has its own subcommand-specific option `-i/--inline` that must appear *after* the subcommand:
```bash
cov-loupe validate -i '->(m) { m.list["files"].all? { |f| f["percentage"] >= 80 } }'
```


---

### --stale Renamed to --staleness

**Change:** The `--stale` option has been renamed to `--staleness`. The short form `-S` is preserved.

**Rationale:** Better describes what the option controls (staleness detection mode) and aligns with internal naming conventions.

**Before (v1.x):**
```bash
simplecov-mcp --stale error list
```

**After (v2.x):**
```bash
simplecov-mcp --staleness error list
# OR use the short form:
simplecov-mcp -S error list
```

**Migration:** Replace `--stale` with `--staleness` (or continue using `-S`).

---

### --source-context Renamed to --context-lines

**Change:** The `--source-context` option has been renamed to `--context-lines`.

**Rationale:** More concise and clearer about what the option controls.

**Before (v1.x):**
```bash
simplecov-mcp --source uncovered --source-context 3 uncovered lib/foo.rb
```

**After (v2.x):**
```bash
simplecov-mcp --source uncovered --context-lines 3 uncovered lib/foo.rb
# OR use the short form:
simplecov-mcp -s uncovered -c 3 uncovered lib/foo.rb
```

**Migration:** Replace `--source-context` with `--context-lines` (or use `-c`).

---

### --source Now Requires Explicit Mode

**Change:** The `--source` option now requires an explicit mode argument (`full` or `uncovered`).

**Rationale:** Eliminates ambiguity about what source display mode is being used.

**Before (v1.x):**
```bash
# Implied 'full' mode
simplecov-mcp --source summary lib/foo.rb
```

**After (v2.x):**
```bash
# Must specify mode explicitly
simplecov-mcp --source full summary lib/foo.rb
# OR
simplecov-mcp --source uncovered summary lib/foo.rb
```

**Migration:** Add an explicit mode (`full` or `uncovered`) after `--source`.

---

### --json Replaced with --format

**Change:** The `--json` flag (and related `-j`, `--pretty-json` flags) have been removed. Use `-f/--format` instead.

**Rationale:** Supports multiple output formats beyond JSON (YAML, awesome_print, etc.) with a consistent interface.

**Before (v1.x):**
```bash
simplecov-mcp --json list
simplecov-mcp -j summary lib/foo.rb
simplecov-mcp --pretty-json list
```

**After (v2.x):**
```bash
simplecov-mcp --format json list
simplecov-mcp -f j summary lib/foo.rb    # Short form
simplecov-mcp --format pretty-json list
simplecov-mcp -f J list                  # Short form for pretty-json
```

**Available formats:**

- `table` (default) - Human-readable table format
- `json` or `j` - Single-line JSON
- `pretty-json` or `J` - Pretty-printed JSON
- `yaml` or `y` - YAML format
- `awesome_print` or `ap` - Colored awesome_print format (requires `awesome_print` gem)

**Migration:** Replace `--json` with `--format json` (or `-f j`). Replace `--pretty-json` with `--format pretty-json` (or `-f J`).

---

### Error Mode Values Changed

**Change:** Error mode enum values have been renamed for clarity:

- `on` → `log`
- `trace` → `debug`

The old values are **no longer supported**.

**Rationale:** More descriptive names that better communicate what each mode does.

**Before (v1.x):**
```bash
simplecov-mcp --error-mode on list
simplecov-mcp --error-mode trace list
```

**After (v2.x):**
```bash
simplecov-mcp --error-mode log list
simplecov-mcp --error-mode debug list
# OR use short forms:
simplecov-mcp --error-mode l list
simplecov-mcp --error-mode d list
```

**Error modes:**

- `off` (or `o`) - Silent, no error logging
- `log` (or `l`) - Log errors to file (default)
- `debug` (or `d`) - Verbose logging with backtraces

**Migration:** Replace `--error-mode on` with `--error-mode log`. Replace `--error-mode trace` with `--error-mode debug`.

---

### --success-predicate Replaced with validate Subcommand

**Change:** The `--success-predicate` flag has been removed. Use the `validate` subcommand instead.

**Rationale:** Better fits the subcommand paradigm and provides a clearer interface for policy validation.

**Before (v1.x):**
```bash
simplecov-mcp --success-predicate policy.rb
```

**After (v2.x):**
```bash
# File-based policy
simplecov-mcp validate policy.rb

# Inline policy (new feature)
simplecov-mcp validate -i '->(m) { m.list["files"].all? { |f| f["percentage"] >= 80 } }'
```

**Migration:** Replace `--success-predicate FILE` with `validate FILE`.

---

### Default Sort Order Changed

**Change:** The default sort order for the `list` command changed from `ascending` to `descending`.

**Rationale:** Most users want to see worst-covered files last so that when scrolling is finished
the worst-covered files are displayed on the screen.

**Before (v1.x):**
```bash
# Shows worst coverage first by default
simplecov-mcp list
```

**After (v2.x):**
```bash
# Shows best coverage first by default
simplecov-mcp list

# To get old behavior (worst first):
simplecov-mcp --sort-order ascending list
simplecov-mcp -o a list  # Short form
```

**Migration:** If you relied on ascending order (worst coverage first), explicitly specify `--sort-order ascending` or `-o a`.

---

## MCP Tool Changes

### stale Parameter Renamed to staleness

**Change:** All MCP tools that accepted a `stale` parameter now use `staleness` instead.

**Rationale:** Aligns with the `CoverageModel` API and CLI option naming.

**Before (v1.x):**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "file_coverage_summary",
    "arguments": {
      "path": "lib/foo.rb",
      "stale": "error"
    }
  }
}
```

**After (v2.x):**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "file_coverage_summary",
    "arguments": {
      "path": "lib/foo.rb",
      "staleness": "error"
    }
  }
}
```

**Affected tools:** All file-based tools (`file_coverage_summary`, `file_coverage_detailed`, `file_coverage_raw`, `file_uncovered_lines`) and aggregate tools (`project_coverage_list`, `project_coverage_totals`).

**Migration:** Replace `"stale"` with `"staleness"` in all MCP tool calls.

---

### Error Mode Values Changed

**Change:** Error mode enum values changed from `['off', 'on', 'trace']` to `['off', 'log', 'debug']`.

**Rationale:** More descriptive names matching CLI changes.

**Before (v1.x):**
```json
{
  "error_mode": "on"
}
```

**After (v2.x):**
```json
{
  "error_mode": "log"
}
```

**Migration:** Replace `"on"` with `"log"`, replace `"trace"` with `"debug"`.

---

### MCP Tool Arguments Use Symbols

**Change:** Internally, MCP tools now normalize enum arguments to symbols (`:off`, `:error`, `:log`, `:debug`) for consistency with the Ruby API.

**Impact:** This is mostly an internal change. MCP clients still send strings in JSON, but if you're using the tools programmatically in Ruby, be aware of the symbol usage.

**Migration:** No action needed for MCP clients. For Ruby API users, see [Ruby API Changes](#ruby-api-changes).

---

## Ruby API Changes

### CLIConfig Renamed to AppConfig

**Change:** The `CLIConfig` class has been renamed to `AppConfig`.

**Rationale:** The configuration is now used by both CLI and MCP modes, not just CLI.

**Before (v1.x):**
```ruby
require 'cov_loupe/cli_config'
config = CovLoupe::CLIConfig.new(root: '.', json: true)
```

**After (v2.x):**
```ruby
require 'cov_loupe/app_config'
config = CovLoupe::AppConfig.new(root: '.', format: :json)
```

**Migration:** Replace `CLIConfig` with `AppConfig` in your code. Update require statements from `'cov_loupe/cli_config'` to `'cov_loupe/app_config'`.

---

### AppConfig Field Changes

**Change:** Several `AppConfig` fields have been renamed or changed:

| Old Field (v1.x)      | New Field (v2.x) | Type Change                          |
|-----------------------|------------------|--------------------------------------|
| `json`                | `format`         | `Boolean` → `Symbol` (`:json`, `:table`, etc.) |
| `stale_mode`          | `staleness`      | Name change only                     |
| `success_predicate`   | (removed)        | Moved to `validate` subcommand       |
| (new)                 | `show_version`   | New field for `-v`/`--version`       |

**Default value changes:**

- `sort_order`: Changed from `:ascending` to `:descending`
- `error_mode`: Changed from `:on` to `:log`

**Before (v1.x):**
```ruby
config = CovLoupe::CLIConfig.new(
  json: true,
  stale_mode: :error,
  error_mode: :on,
  sort_order: :ascending
)
```

**After (v2.x):**
```ruby
config = CovLoupe::AppConfig.new(
  format: :json,
  staleness: :error,
  error_mode: :log,
  sort_order: :descending  # New default
)
```

**Migration:** Update field names when constructing `AppConfig`. Note the new defaults.

---

## Behavioral Changes

### Context Lines Validation

**Change:** The `--context-lines` option (formerly `--source-context`) now raises an `ArgumentError` if given a negative value. Previously, negative values were silently clamped to zero.

**Rationale:** Fail fast and provide clear feedback for invalid input.

**Before (v1.x):**
```bash
# Silently clamped to 0
simplecov-mcp --source-context -5 uncovered lib/foo.rb
```

**After (v2.x):**
```bash
# Raises ArgumentError
simplecov-mcp --context-lines -5 uncovered lib/foo.rb
# Error: Context lines must be non-negative (got: -5)
```

**Migration:** Ensure `--context-lines` values are non-negative (>= 0).

---

## Migration Guide

### Quick Checklist

- [ ] Move all global options before subcommands in CLI invocations
- [ ] Replace `--stale` with `--staleness` (or continue using `-S`)
- [ ] Replace `--source-context` with `--context-lines` (or use `-c`)
- [ ] Add explicit mode to `--source` (either `full` or `uncovered`)
- [ ] Replace `--json` with `--format json` (or `-f j`)
- [ ] Replace `--error-mode on` with `--error-mode log`
- [ ] Replace `--error-mode trace` with `--error-mode debug`
- [ ] Replace `--success-predicate FILE` with `validate FILE`
- [ ] Update MCP tool calls: rename `stale` to `staleness`
- [ ] Update MCP tool calls: replace error mode `"on"` with `"log"`, `"trace"` with `"debug"`
- [ ] Update Ruby code: rename `CLIConfig` to `AppConfig`
- [ ] Update Ruby code: rename `json` field to `format`, `stale_mode` to `staleness`
- [ ] Explicitly set `--sort-order ascending` if you need worst-coverage-first sorting
- [ ] Ensure `--context-lines` values are non-negative

### Script Migration Example

**Before (v1.x):**
```bash
#!/bin/bash
simplecov-mcp list --json --stale error --sort-order ascending
simplecov-mcp summary lib/foo.rb --json
simplecov-mcp uncovered lib/bar.rb --source=uncovered --source-context 3
simplecov-mcp --success-predicate policy.rb
```

**After (v2.x):**
```bash
#!/bin/bash
simplecov-mcp --format json --staleness error --sort-order ascending list
simplecov-mcp --format json summary lib/foo.rb
simplecov-mcp --source uncovered --context-lines 3 uncovered lib/bar.rb
simplecov-mcp validate policy.rb
```

### Environment Variable Migration

**Before (v1.x):**
```bash
export SIMPLECOV_MCP_OPTS="--stale error --json"
```

**After (v2.x):**
```bash
export COV_LOUPE_OPTS="--staleness error --format json"
```

---

## Getting Help

If you encounter issues migrating to v2.0:

1. Check the [Troubleshooting](../TROUBLESHOOTING.md) guide
2. Review the [CLI Usage](../CLI_USAGE.md) for complete CLI reference
3. See [MCP Integration](../MCP_INTEGRATION.md) for MCP tool documentation
4. Open an issue at https://github.com/keithrbennett/simplecov-mcp/issues

---

**See also:**

- [RELEASE_NOTES.md](../../../RELEASE_NOTES.md) - Full release notes with new features
- [CLI Usage](../CLI_USAGE.md) - Complete CLI reference
- [MCP Integration](../MCP_INTEGRATION.md) - MCP tool reference
