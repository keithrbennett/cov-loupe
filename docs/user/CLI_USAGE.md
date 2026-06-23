# CLI Usage Guide

[Back to main README](../index.md)

Complete reference for using cov-loupe from the command line.

> Docs use `clp` as a shortcut pointing at the demo fixture with partial coverage:
> `alias clp='cov-loupe -R docs/fixtures/demo_project'`  # -R = --root
> Replace `clp` with `cov-loupe` to run commands against your own project.
> The demo fixture is a small Rails-like project in `docs/fixtures/demo_project` with intentional coverage gaps for testing `--tracked-globs`.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Subcommands](#subcommands)
- [Global Options](#global-options)
- [Output Formats](#output-formats)
- [Environment Variables](#environment-variables)
- [Examples](#examples)

## Quick Reference

```sh
# Show coverage table for all files (default or 'l')
clp
clp list
clp l

# Check specific file ('summary' or 's')
clp summary app/models/order.rb
clp s app/models/order.rb

# Find uncovered lines ('uncovered' or 'u')
clp uncovered app/models/order.rb
clp u app/models/order.rb

# Get detailed per-line coverage ('detailed' or 'd')
clp detailed app/models/order.rb
clp d app/models/order.rb

# Get raw SimpleCov data ('raw' or 'r')
clp raw app/models/order.rb
clp r app/models/order.rb

# Get project totals ('totals' or 't')
clp totals
clp t
clp -fp t

# Evaluate coverage policy ('validate' or 'v')
clp validate coverage_policy.rb
clp v coverage_policy.rb
clp v -i '->(m) { m.project_totals["lines"]["percentage"] >= 85 }'

# Show version (no subcommand; use -v or --version)
clp -v
clp --version

# Get help
clp -h  # -h = --help

# Print canonical resource paths/URLs (stdout only)
clp -p repo
clp --path-for repo
clp --path-for docs
clp --path-for docs-local
```

## Subcommands

### `list`, `l`

Show coverage summary for all files (default subcommand).

```sh
clp list
clp l
clp -o d l  # -o = --sort-order, d = descending
clp -fp l           
```

Default sort order is descending (highest coverage first) so the lowest-coverage files stay visible at the bottom of the scrollback.

**Options:**

| Short   | Long                     | Description                                           |
|---------|--------------------------|-------------------------------------------------------|
| `-o`    | `--sort-order`           | Sort by coverage percentage (ascending or descending) |
| `-g`    | `--tracked-globs`        | Filter to specific file patterns                      |
| `-S`    | `--raise-on-stale`       | Raise error if coverage is stale (default false)      |
| `-fp`   | `--format pretty-json`   | Output as pretty-printed JSON                         |
| `-fj`   | `--format json`          | Output as single-line JSON                            |
| `-f y`  | `--format yaml`          | Output as YAML                                        |
| `-f ap` | `--format amazing_print` | Output using AmazingPrint                             |

**Output (table format):**
```
┌────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                   │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ app/models/user.rb                     │  100.00% │         6 │       6 │       │
│ lib/api/client.rb                      │   88.89% │         8 │       9 │       │
│ app/models/order.rb                    │   85.71% │         6 │       7 │       │
│ lib/ops/jobs/report_job.rb             │   80.00% │         4 │       5 │       │
│ lib/payments/processor.rb              │   80.00% │         4 │       5 │       │
│ app/controllers/orders_controller.rb   │   70.00% │         7 │      10 │       │
│ lib/payments/refund_service.rb         │   60.00% │         3 │       5 │       │
└────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 7, ok 7, stale 0
```

**Stale indicators:** missing (missing file), newer (timestamp mismatch), length_mismatch (line count mismatch), error (staleness check error)

### `summary <path>`, `s <path>`

Show covered/total/percentage for a specific file.

```sh
clp summary app/models/order.rb
clp s app/models/order.rb
clp -fp s app/models/order.rb
clp -s full s app/models/order.rb  # -s = --source
```

**Arguments:**
- `<path>` - File path (relative to project root or absolute)

**Options:**

| Short | Long             | Description                                |
|-------|------------------|--------------------------------------------|
| `-fp`   | `--format pretty-json` | Output as pretty-printed JSON         |
| `-fj` | `--format json`        | Output as single-line JSON            |
| `-f y` | `--format yaml`        | Output as YAML                        |
| `-f ap` | `--format amazing_print` | Output using AmazingPrint                             |
| `-s`  | `--source MODE`  | Include source code (full, uncovered, or none)    |

**Output (default format):**
```
┌───────────────────────┬──────────┬─────────┬───────┬───────┐
│ File                  │        % │ Covered │ Total │ Stale │
├───────────────────────┼──────────┼─────────┼───────┼───────┤
│ app/models/order.rb   │   85.71% │       6 │     7 │       │
└───────────────────────┴──────────┴─────────┴───────┴───────┘
```

**Output (JSON format):**
```json
{
  "file": "app/models/order.rb",
  "summary": {
    "covered": 6,
    "total": 7,
    "percentage": 85.71
  },
  "stale": "ok"
}
```

### `uncovered <path>`, `u <path>`

Show uncovered line numbers for a specific file.

```sh
clp uncovered app/controllers/orders_controller.rb
clp u app/controllers/orders_controller.rb
clp -s uncovered u app/controllers/orders_controller.rb  # -s = --source
clp -s uncovered -c 3 u app/controllers/orders_controller.rb  # -s = --source, -c = --context-lines
```

**Arguments:**
- `<path>` - File path (relative to project root or absolute)

**Options:**

| Short   | Long                     | Description                                          |
|---------|--------------------------|------------------------------------------------------|
| `-s`    | `--source MODE`          | Show source (full, uncovered, none)                 |
| `-c`    | `--context-lines N`      | Lines of context around uncovered lines (default: 2) |
| `-C`    | `--color BOOLEAN`        | Enable (`true`)/disable (`false`) syntax coloring    |
| `-fp`   | `--format pretty-json`   | Output as pretty-printed JSON                        |
| `-fj`   | `--format json`          | Output as single-line JSON                           |
| `-f y`  | `--format yaml`          | Output as YAML                                       |
| `-f ap` | `--format amazing_print` | Output using AmazingPrint                             |

**Output (default format):**
```
File:            app/controllers/orders_controller.rb
Uncovered lines: 14, 15, 20
Summary:         70.0%      7/10
```

**Output (with source):**
```
File:            app/controllers/orders_controller.rb
Uncovered lines: 14, 15, 20
Summary:         70.0%      7/10

  Line     | Source
  ------+-----------------------------------------------------------
    14  · |       def show(id)
    15  · |         @repo.find(id)
    16  ✓ |       end
    17    |
    18  ✓ |       def cancel(id)
    19  ✓ |         order = @repo.find(id)
    20  · |         return :missing unless order
```

**Legend:**
- `✓` - Line is covered
- `·` - Line is not covered
- ` ` - Line is not executable (comments, blank lines)

### `detailed <path>`, `d <path>`

Show per-line coverage with hit counts.

```sh
clp detailed app/models/order.rb
clp d app/models/order.rb
clp -fp d app/models/order.rb
clp -s full d app/models/order.rb  # -s = --source
```

**Arguments:**
- `<path>` - File path (relative to project root or absolute)

**Options:**

| Short   | Long                     | Description                   |
|---------|--------------------------|-------------------------------|
| `-fp`   | `--format pretty-json`   | Output as pretty-printed JSON |
| `-fj`   | `--format json`          | Output as single-line JSON    |
| `-f y`  | `--format yaml`          | Output as YAML                |
| `-f ap` | `--format amazing_print` | Output using AmazingPrint                             |
| `-s`    | `--source MODE`          | Include source code           |

**Output (default format):**
```
File: app/models/order.rb
Coverage: 6/7 lines (85.71%)

┌──────┬──────┬─────────┐
│ Line │ Hits │ Covered │
├──────┼──────┼─────────┤
│    6 │    1 │   yes   │
│    7 │    1 │   yes   │
│    8 │    1 │   yes   │
│   11 │    1 │   yes   │
│   12 │    1 │   yes   │
│   15 │    1 │   yes   │
│   16 │    0 │   no    │
└──────┴──────┴─────────┘
```

**Output (JSON format):**
```json
{
  "file": "app/models/order.rb",
  "lines": [
    { "line": 6, "hits": 1, "covered": true },
    { "line": 7, "hits": 1, "covered": true },
    { "line": 8, "hits": 1, "covered": true },
    { "line": 11, "hits": 1, "covered": true },
    { "line": 12, "hits": 1, "covered": true },
    { "line": 15, "hits": 1, "covered": true },
    { "line": 16, "hits": 0, "covered": false }
  ],
  "summary": {
    "covered": 6,
    "total": 7,
    "percentage": 85.71
  },
  "stale": "ok"
}
```

### `raw <path>`, `r <path>`

Show the raw SimpleCov lines array.

```sh
clp raw app/models/order.rb
clp r app/models/order.rb
clp -fp r app/models/order.rb
```

**Arguments:**
- `<path>` - File path (relative to project root or absolute)

**Output (default format):**
```
File: app/models/order.rb
[nil, nil, nil, nil, nil, 1, 1, 1, nil, nil, 1, 1, nil, nil, 1, 0, nil, nil, nil, nil]
```

**Output (JSON format):**
```json
{
  "file": "app/models/order.rb",
  "lines": [null, null, null, null, null, 1, 1, 1, null, null, 1, 1, null, null, 1, 0, null, null, null, null],
  "stale": "ok"
}
```

**Array explanation:**
- Integer (e.g., `1`, `5`) - Number of times line was executed
- `0` - Line is executable but was not executed
- `null` - Line is not executable (comment, blank line)

### `totals`, `t`

Show aggregated totals for all tracked files.

```sh
clp totals
clp t
clp -fp t
clp -g "lib/ops/jobs/*.rb" t  # -g = --tracked-globs
```

**Output (default format):**
```
Tracked globs:
  - lib/**/*.rb
  - app/**/*.rb
  - src/**/*.rb

Totals
┌──────────┬───────┬─────────┬───────────┬────────┐
│ Metric   │ Total │ Covered │ Uncovered │      % │
├──────────┼───────┼─────────┼───────────┼────────┤
│ Lines    │    47 │      38 │         9 │ 80.85% │
│ Files    │     7 │       7 │         0 │        │
└──────────┴───────┴─────────┴───────────┴────────┘

File breakdown:
  With coverage: 7 total, 7 ok, 0 stale
    Stale: missing on disk = 0, newer than coverage = 0, line mismatch = 0, unreadable = 0
  Without coverage: 0 total
    Missing from coverage = 0, unreadable = 0, skipped (errors) = 0
```

**Tracked globs (shown when tracking is enabled):**
```
Tracked globs:
  - lib/**/*.rb
  - app/**/*.rb
```

**Output (JSON format):**
```json
{
  "lines": { "total": 47, "covered": 38, "uncovered": 9, "percentage": 80.85 },
  "tracking": { "enabled": true, "globs": ["lib/**/*.rb", "app/**/*.rb"] },
  "files": {
    "total": 7,
    "with_coverage": {
      "total": 7,
      "ok": 7,
      "stale": {
        "total": 0,
        "by_type": {
          "missing_from_disk": 0,
          "newer": 0,
          "length_mismatch": 0,
          "unreadable": 0
        }
      }
    },
    "without_coverage": {
      "total": 0,
      "by_type": {
        "missing_from_coverage": 0,
        "unreadable": 0,
        "skipped": 0
      }
    }
  }
}
```

**Notes:**
- `lines` are based on fresh coverage entries only.
- `with_coverage.stale.by_type` uses readable labels: `missing_from_disk`, `newer`,
  `length_mismatch`, `unreadable`.
- `without_coverage` is only present when tracking is enabled (tracked globs provided).
- Respects `-g` / `--tracked-globs` when you only want to aggregate a subset of files.
- Totals exclude stale files (`"missing"`, `"newer"`, `"length_mismatch"`, `"error"`) so the aggregate reflects only fresh coverage data.
- Honors `-S` / `--raise-on-stale` to raise if coverage data is out of date.

## Global Options

These options work with all subcommands.

### `-r, --resultset PATH`

Path to the `.resultset.json` file or a directory containing it.

For a detailed explanation of how to configure the resultset location, including the default search path, environment variables, and MCP configuration, see the [Configuring the Resultset](../index.md#configuring-the-resultset) section in the main README.

### `-R, --root PATH`

Project root directory (default: current directory).

```sh
clp -R /path/to/project  # -R = --root
```

### `-p`, `--path-for NAME`

Print a canonical resource path or URL to stdout and exit immediately.

Supported names:
- `repo` - public GitHub repository URL
- `docs` - public documentation site URL
- `docs-local` - absolute path to local `README.md`

```sh
clp -p repo
clp --path-for repo
clp --path-for docs
clp --path-for docs-local
```

This option is designed for shell composition and prints only the value:

```sh
open "$(clp --path-for docs)"
```

### `-fp`

Output as pretty-printed JSON instead of human-readable format.

```sh
clp -fp summary lib/api/client.rb
```

Useful for:
- Parsing in scripts
- Integration with other tools
- Machine consumption

### `-o, --sort-order ORDER`

Sort order for `list` subcommand.

**Values:**
- `descending`, `d` - Highest coverage first (default)
- `ascending`, `a` - Lowest coverage first

```sh
clp -o d list  # d = descending (default)
clp -o a list  # a = ascending
```

### `-s, --source MODE`

Include source code in output.

**Modes:**

| Short | Long        | Description                                         |
|-------|-------------|-----------------------------------------------------|
| `f`   | `full`      | Show all source lines                               |
| `u`   | `uncovered` | Show only uncovered lines with context              |
| `n`   | `none`      | Disable source code display                         |

```sh
# Show full source
clp -s full summary lib/api/client.rb      # -s = --source
clp -s f summary lib/api/client.rb         # f = full

# Show only uncovered lines
clp -s u uncovered lib/api/client.rb       # u = uncovered

# Disable source display (override earlier --source setting)
clp -s n summary lib/api/client.rb        # n = none
clp -s f -s n summary lib/api/client.rb   # later -s n disables earlier -s f
```

### `-c, --context-lines N`

Number of context lines around uncovered code (for `-s uncovered` / `--source uncovered`). Must be a non-negative integer.

```sh
clp -s u -c 3 uncovered lib/api/client.rb  # -s u = uncovered, -c = --context-lines
```

**Default:** 2 lines

### Boolean Flags (`--color` / `-C`, `--raise-on-stale`)

These options require explicit boolean values. Recognized literals:

| true   | false   |
|--------|---------|
| `yes`  | `no`    |
| `y`    | `n`     |
| `true` | `false` |
| `t`    | `f`     |
| `on`   | `off`   |
| `+`    | `-`     |
| `1`    | `0`     |

```sh
clp --color false           # disable color
clp --raise-on-stale yes    # enforce stale coverage failures
```

### `-C, --color BOOLEAN`

Enable or disable ANSI color codes in source output. Requires an explicit boolean value.

```sh
clp -s uncovered --color true uncovered lib/api/client.rb
clp -s uncovered -C false uncovered lib/api/client.rb
```

**Default:** Colors enabled if output is a TTY

### `-S, --raise-on-stale BOOLEAN`

Raise error if coverage is stale. Requires an explicit boolean value. Default is `false` (only report staleness in output).

```sh
# Enable raising an error if coverage is stale
clp -S true
clp --raise-on-stale yes

# Explicitly disable raising an error (useful to override COV_LOUPE_OPTS)
clp --raise-on-stale false
```

**Staleness conditions:**
- **"missing"** (Missing): Source file no longer exists on disk
- **"newer"** (Timestamp): Source file modified after coverage was generated
- **"length_mismatch"** (Length): Source file line count differs from coverage data
- **"error"** (Error): Staleness check failed due to permission or I/O errors
- Tracked files missing from coverage (with --tracked-globs)

### `-g, --tracked-globs PATTERNS`

Comma-separated glob patterns for files that should be tracked.

**Default:** `[]` (empty - shows all files in the resultset)

**Why no default patterns?**
1. **Transparency** - Shows all coverage data without hiding files that don't match assumptions
2. **Avoids false positives** - Broad patterns like `**/*.rb` flag migrations, bin scripts, etc. as "missing"
3. **Project variety** - Coverage patterns vary by project structure (lib/, app/, src/, config/, etc.)

**Important:** Files lacking any coverage at all (not loaded during tests) will not appear in the resultset and therefore won't be visible with the default empty array. To detect such files, you must set `--tracked-globs` to match the files you expect to have coverage.

**Best practice:** Match your SimpleCov configuration by setting `COV_LOUPE_OPTS`:

```ruby
# In spec_helper.rb or similar
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/test/'
  track_files 'lib/**/*.rb'
  track_files 'app/**/*.rb'
end
```

```sh
# In your shell config (.bashrc, .zshrc, etc.)
# Match the track_files patterns above
export COV_LOUPE_OPTS="--tracked-globs lib/**/*.rb,app/**/*.rb"
```

**Usage:**

```sh
# Use environment variable for project-wide default
export COV_LOUPE_OPTS="--tracked-globs lib/**/*.rb,app/**/*.rb"
clp list  # Uses globs from env var

# Or specify per-command
clp -g "lib/api/**/*.rb" list

# Multiple patterns
clp -g "lib/**/*.rb,app/models/**/*.rb" list

# Export for CI (with globs to match SimpleCov)
clp -g "lib/**/*.rb,app/**/*.rb" -fp list > coverage.json
```

**Use cases:**
- **Exclude unwanted results** - Narrow focus to a subsystem or layer
- **Include files without coverage** - Report files that should be tracked but aren't in the resultset
- **CI validation** - Use with `-S`/`--raise-on-stale` to catch coverage gaps

**Important:** The `missing_tracked_files` array (in `list` output) only includes files that:
1. Match the tracked globs
2. Exist in the filesystem
3. Are NOT in the coverage resultset

Without globs, this array is empty (no expectations = no violations).

### `-l, --log-file PATH`

Log file location. Use 'stderr' to log to a standard stream.
Use ':off' to disable logging entirely (cross-platform alternative to /dev/null).
Logging to 'stdout' is not permitted because it would corrupt command output.

```sh
clp -l /var/log/simplecov.log  # -l = --log-file
clp -l stderr                   # Log to standard error
clp -l :off                     # Disable logging entirely
```

**Default:** `./cov_loupe.log`

**Warning:** Log files may grow unbounded in long-running or CI usage. Consider using a log rotation tool or periodically cleaning up the log file if this is a concern.

### `-e, --error-mode MODE`

Error handling verbosity.

**Modes:**

| Short | Long    | Description                                        |
|-------|---------|----------------------------------------------------|
|       | `off`   | Silent (no error logging)                          |
| `l`   | `log`   | Log errors without stack traces (default)          |
| `d`   | `debug` | Log errors with full stack traces                  |

```sh
clp --error-mode debug summary lib/api/client.rb
clp -e debug summary lib/api/client.rb  # -e = --error-mode
clp -edebug summary lib/api/client.rb   # attached short option form
```

### `-O, --output-chars MODE`

Control output character encoding for ASCII-only environments.

**Modes:**

| Short | Long        | Description                                       |
|-------|-------------|---------------------------------------------------|
| `d`   | `default`   | Auto-detect terminal UTF-8 support (default)      |
| `f`   | `fancy`     | Force Unicode output with box-drawing characters  |
| `a`   | `ascii`     | Force ASCII-only output with transliteration      |

```sh
# Default output character mode (auto-detects UTF-8 support)
clp list

# Force ASCII mode (for legacy terminals or CI)
clp -O ascii list
clp -O a list  # a = ascii

# Force fancy mode (Unicode characters)
clp -O fancy list
clp -O f list  # f = fancy
```

**What gets converted in ASCII mode:**
- Table borders (│ ─ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ → | - + + + + + + + + +)
- Source code markers (✓ · → + -)
- Error messages and file paths
- All formatted output (tables, source, JSON, YAML)

**What does NOT get converted:**
- Log files (preserved in original encoding for debugging fidelity)
- Gem post-install message

**Use cases:**
- **CI/CD systems** with ASCII-only terminals: `clp -O ascii list`
- **Windows** with legacy encoding: `clp -O ascii summary lib/api/client.rb`
- **Piped output** to files: `clp -O ascii list > coverage.txt`
- **Force Unicode** even if terminal detection fails: `clp -O fancy list`

**Note:** The default mode auto-detects whether your terminal supports UTF-8. If Unicode characters appear garbled or as question marks, try `clp -O ascii`.

### `-m, --mode MODE`

Specify execution mode: `cli` or `mcp` (default: `cli`). Use `--mode mcp` to run as an MCP server.
In v4.0.0+, automatic mode detection was removed; you must explicitly specify `--mode mcp` to run the MCP server.

```sh
clp -m mcp               # MCP server mode (required for MCP), short option form
clp --mode mcp           # MCP server mode (required for MCP), long option form
clp -m cli list          # CLI mode (default), can use to override environment variable
```

### `validate <file> | -i <code>`, `v <file> | -i <code>`

Validate coverage against custom policies for CI/CD enforcement.

> **⚠️ SECURITY WARNING**
>
> Validation predicates execute as **arbitrary Ruby code with full system privileges**. They have unrestricted access
> to file system, network, system commands, and environment variables.
>
> **Only use predicate files from trusted sources.**
> Review predicates before use, especially in CI/CD environments.

The predicate must be a callable (lambda, proc, or object with `#call` method) that receives a `CoverageModel` and returns `true` or `false`.

**Predicate return values:**
- `true` - Coverage meets your criteria (CLI exits with code 0)
- `false` - Coverage fails your criteria (CLI exits with code 1)
- Exception raised - Predicate error (CLI exits with code 2)

**File mode (most common):**
```sh
# Use example predicate
clp validate examples/success_predicates/all_files_above_threshold_predicate.rb
clp v examples/success_predicates/all_files_above_threshold_predicate.rb

# In CI/CD
cov-loupe validate coverage_policy.rb
cov-loupe v coverage_policy.rb
```

**String mode (inline code):**
```sh
# Simple inline validation
clp validate -i '->(m) { m.list["files"].all? { |f| f["percentage"] >= 80 } }'
clp v -i '->(m) { m.list["files"].all? { |f| f["percentage"] >= 80 } }'

# With global options
clp -r coverage validate -i '->(m) { m.list["files"].size > 0 }'
clp -r coverage v -i '->(m) { m.list["files"].size > 0 }'
```

**Example predicate file:**
```ruby
# coverage_policy.rb
->(model) do
  model.list["files"].all? { |f| f['percentage'] >= 80 }
end
```

See [examples/success_predicates/](../examples/success_predicates.md) for more examples.

## Output Formats

### Table Format

Default for `list` subcommand. Uses Unicode box-drawing characters.

```
┌──────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                             │        % │   Covered │   Total │ Stale │
├──────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ lib/payments/refund_service.rb   │   60.00% │         3 │       5 │       │
└──────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
```

### JSON Format

Machine-readable output. Paths are relative to project root.

```json
{
  "file": "app/models/order.rb",
  "summary": {
    "covered": 6,
    "total": 7,
    "percentage": 85.71
  },
  "stale": "ok"
}
```

**Staleness values:**
- `"ok"` - Coverage data is current
- `"missing"` - File missing (no longer exists on disk)
- `"newer"` - Timestamp mismatch (file modified after coverage)
- `"length_mismatch"` - Length mismatch (line count differs)

### Source Display

With `--source` flag, shows annotated source code:

```
  Line     | Source
  ------+-----------------------------------------------------------
     1  ✓ | class User
     2  · |   def initialize  # Not covered
     3  ✓ |     # ...
```

## Environment Variables

### `COV_LOUPE_OPTS`

Default command-line options applied to all invocations.

**Format:** Shell-style string containing any valid CLI options

```sh
export COV_LOUPE_OPTS="--resultset coverage -fp"
clp summary lib/api/client.rb  # Automatically uses options above
```

**Precedence:** Command-line arguments override environment options

```sh
# Environment sets -fp; explicit CLI options still take precedence
export COV_LOUPE_OPTS="-fp"
clp summary lib/api/client.rb  # Uses JSON (from env)
clp -f table summary lib/api/client.rb  # Explicit override to table format
```

**Examples:**
```sh
# Default resultset location
export COV_LOUPE_OPTS="-r build/coverage"

# Enable detailed error logging
export COV_LOUPE_OPTS="--error-mode debug"

# Paths with spaces
export COV_LOUPE_OPTS='-r "/path with spaces/coverage"'

# Multiple options
export COV_LOUPE_OPTS="-r coverage -S true -fp"
```



## Examples

### Basic Coverage Check

```sh
# Show all files sorted by highest coverage first (default)
clp

# Find the 5 files with worst coverage (account for header/footer)
clp list | tail -7
```

### Detailed File Investigation

```sh
# Check a specific file
clp summary lib/payments/refund_service.rb

# See which lines aren't covered
clp uncovered lib/payments/refund_service.rb

# View uncovered code in context
clp -s uncovered -c 3 uncovered lib/payments/refund_service.rb

# Get detailed hit counts
clp detailed lib/payments/refund_service.rb
```

### JSON Output for Scripts

```sh
# Get JSON for parsing
clp -fp list > coverage.json

# Extract files below threshold
clp -fp list | jq '.files[] | select(.percentage < 80)'

# Ruby alternative:
clp -fp list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].select { |f| f["percentage"] < 80 }.each do |f|
    puts JSON.pretty_generate(f)
  end
'

# Rexe alternative:
clp -fp list | rexe -ij -mb -oJ 'self["files"].select { |f| f["percentage"] < 80 }'

# Count files below 80% coverage
clp -fp list | jq '[.files[] | select(.percentage < 80)] | length'

# Ruby alternative:
clp -fp list | ruby -r json -e '
  puts JSON.parse($stdin.read)["files"].count { |f| f["percentage"] < 80 }
'

# Rexe alternative:
clp -fp list | rexe -ij -mb -op 'self["files"].count { |f| f["percentage"] < 80 }'
```

### Filtering and Sorting

```sh
# Show only lib/ files
clp -g "lib/**/*.rb" list

# Show files sorted by highest coverage
clp -o d list

# Check specific directory
clp -g "lib/payments/**/*.rb" list
```



### Staleness Checking

```sh
# Check if coverage is stale (for CI/CD)
clp -S true

# Check with specific file patterns
clp -S true -g "lib/payments/**/*.rb,lib/ops/jobs/**/*.rb" list

# See which files are stale (don't error)
clp list  # Stale column shows missing/newer/length_mismatch/error markers
```

### Source Code Display

```sh
# Show full source with coverage markers
clp -s full summary lib/api/client.rb

# Show only uncovered lines with context
clp -s uncovered uncovered lib/api/client.rb

# More context around uncovered code
clp -s uncovered -c 5 uncovered lib/api/client.rb

# Without colors (for logging)
clp -s full --color false uncovered lib/api/client.rb
```

### CI/CD Integration

```sh
# Fail build if coverage is stale
clp -S true || exit 1

# Generate JSON report for artifact
clp -fp list > artifacts/coverage-report.json

# Check specific directory in monorepo
clp -R services/api -r services/api/coverage  # -R = --root, -r = --resultset
```

### Debugging

```sh
# Verbose error output
clp --error-mode debug summary lib/api/client.rb

# Custom log file (--log-file or -l)
clp -l /tmp/simplecov-debug.log summary lib/api/client.rb

# Check what resultset is being used
clp --error-mode debug 2>&1 | grep resultset
```

## Exit Codes

- `0` - Success
- `1` - Error (file not found, coverage data missing, stale coverage with `-S` / `--raise-on-stale`, etc.)

## Next Steps

- **[Library API](LIBRARY_API.md)** - Use in Ruby code
- **[Examples](EXAMPLES.md)** - More usage examples and recipes
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
