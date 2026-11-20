# CLI Usage Guide

[Back to main README](../../README.md)

Complete reference for using cov-loupe from the command line.

> Docs use `clp` as a shortcut pointing at the demo fixture with partial coverage:
> `alias clp='cov-loupe -R docs/fixtures/demo_project'`  # -R = --root
> Run the examples from the root of a cov-loupe checkout, since the alias's path is relative. Without the gem
> installed, use `alias clp='bundle exec exe/cov-loupe -R docs/fixtures/demo_project'` instead.
> Replace `clp` with `cov-loupe` to run commands against your own project.
> The demo fixture is a small Rails-like project in `docs/fixtures/demo_project` with intentional coverage gaps for testing `--file-globs`.
> Its coverage timestamp is deliberately set far in the future, so the outputs below are reproducible on a fresh clone.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Subcommands](#subcommands)
- [Global Options](#global-options)
- [Output Formats](#output-formats)
- [Environment Variables](#environment-variables)
- [Examples](#examples)
- [Exit Codes](#exit-codes)
- [Next Steps](#next-steps)

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
clp -fJ t

# Evaluate coverage policy ('validate' or 'v')
clp validate examples/success_predicates/project_coverage_minimum_predicate.rb
clp v examples/success_predicates/project_coverage_minimum_predicate.rb
clp v -i '->(m) { m.project_totals["percentage"].to_f >= 85 }'
# validate prints no result (only what the predicate itself prints); check the exit code (0 pass, 3 fail). On the demo fixture
# (80.85% total) these minimum-85% checks fail, so they exit 3.
echo $?

# Show version (no subcommand; use -v or --version; `v` without a dash runs validate)
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

Note: `-l` with a dash sets `--log-file`; `l` without a dash runs the `list` subcommand abbreviation.

## Subcommands

### `list`, `l`

Show coverage summary for all files (default subcommand).

```sh
clp list
clp l
clp -o d l  # -o = --sort-order, d = descending
clp -fJ l           
```

Default sort order is descending (highest coverage first) so the lowest-coverage files stay visible at the bottom of the scrollback. Files with no coverable lines (`n/a`) sort above 100%; see [Sorting Coverage Lists with n/a Entries](ADVANCED_USAGE.md#sorting-coverage-lists-with-na-entries).

**Options:**

| Short  | Long                     | Description                                           |
|--------|--------------------------|-------------------------------------------------------|
| `-o`   | `--sort-order`           | Sort by coverage percentage (ascending or descending) |
| `-g`   | `--file-globs`           | Limit results to matching files; report matching files with no coverage |
| `-S`   | `--raise-on-stale BOOLEAN` | Raise error if coverage is stale, a file matching `-g` is not in coverage data, or a row is skipped (default false) |
| `-f`   | `--format`               | Output format, e.g. `J` (pretty JSON), `j`, `y`, `a`; see [Output Formats](#output-formats) |

**Output (table format):**
```
┌────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                   │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ app/models/user.rb                     │  100.00% │         6 │       6 │       │
│ lib/api/client.rb                      │   88.88% │         8 │       9 │       │
│ app/models/order.rb                    │   85.71% │         6 │       7 │       │
│ lib/ops/jobs/report_job.rb             │   80.00% │         4 │       5 │       │
│ lib/payments/processor.rb              │   80.00% │         4 │       5 │       │
│ app/controllers/orders_controller.rb   │   70.00% │         7 │      10 │       │
│ lib/payments/refund_service.rb         │   60.00% │         3 │       5 │       │
└────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 7, ok 7, stale 0
```

**Output (JSON format, condensed here; `-fJ` prints it fully indented):**
```json
{
  "schema_version": 1,
  "files": [
    { "file": "app/models/user.rb", "covered": 6, "uncovered": 0, "total": 6, "percentage": 100.0, "stale": "ok" },
    { "file": "lib/api/client.rb", "covered": 8, "uncovered": 1, "total": 9, "percentage": 88.88, "stale": "ok" },
    { "file": "app/models/order.rb", "covered": 6, "uncovered": 1, "total": 7, "percentage": 85.71, "stale": "ok" },
    { "file": "lib/ops/jobs/report_job.rb", "covered": 4, "uncovered": 1, "total": 5, "percentage": 80.0, "stale": "ok" },
    { "file": "lib/payments/processor.rb", "covered": 4, "uncovered": 1, "total": 5, "percentage": 80.0, "stale": "ok" },
    { "file": "app/controllers/orders_controller.rb", "covered": 7, "uncovered": 3, "total": 10, "percentage": 70.0, "stale": "ok" },
    { "file": "lib/payments/refund_service.rb", "covered": 3, "uncovered": 2, "total": 5, "percentage": 60.0, "stale": "ok" }
  ],
  "skipped_files": [],
  "not_in_coverage_files": [],
  "newer_files": [],
  "deleted_files": [],
  "length_mismatch_files": [],
  "unreadable_files": [],
  "timestamp_status": "ok"
}
```

**Stale indicators:** deleted (source file deleted), newer (timestamp mismatch), length_mismatch (line count mismatch), unreadable (source file could not be read, or its staleness check failed)

**Skipped rows:** a coverage row with invalid data is left out of the report. It is listed in the exclusions summary on `stderr` (table format) or in `skipped_files` (structured formats, with a warning on `stderr`). The table-format exclusions summary also lists files not in coverage data and stale files, and a table with stale rows ends with a `Staleness:` legend line. With `--raise-on-stale true`, such a row is an error instead.

### `summary <path>`, `s <path>`

Show covered/total/percentage for a specific file.

```sh
clp summary app/models/order.rb
clp s app/models/order.rb
clp -fJ s app/models/order.rb
clp -s full s app/models/order.rb  # -s = --source
```

**Arguments:**

- `<path>` - File path (relative to project root or absolute)

**Options:**

| Short  | Long                     | Description                                    |
|--------|--------------------------|------------------------------------------------|
| `-f`   | `--format`               | Output format, e.g. `J` (pretty JSON), `j`, `y`, `a`; see [Output Formats](#output-formats) |
| `-s`   | `--source MODE`          | Include source code (full, uncovered, or none) |
| `-n`   | `--context-lines N`      | Lines of context around uncovered lines with `-s uncovered` (default: 2) |
| `-C`   | `--color BOOLEAN`        | Enable (`true`)/disable (`false`) coverage marker colors |

**Output (default format):**
```
┌─────────────────────┬────────┬─────────┬───────┬───────┐
│ File                │      % │ Covered │ Total │ Stale │
├─────────────────────┼────────┼─────────┼───────┼───────┤
│ app/models/order.rb │ 85.71% │       6 │     7 │       │
└─────────────────────┴────────┴─────────┴───────┴───────┘
```

**Output (JSON format):**
```json
{
  "schema_version": 1,
  "file": "app/models/order.rb",
  "covered": 6,
  "uncovered": 1,
  "total": 7,
  "percentage": 85.71,
  "stale": "ok"
}
```

### `uncovered <path>`, `u <path>`

Show uncovered line numbers for a specific file.

```sh
clp uncovered app/controllers/orders_controller.rb
clp u app/controllers/orders_controller.rb
clp -s uncovered u app/controllers/orders_controller.rb  # -s = --source
clp -s uncovered -n 3 u app/controllers/orders_controller.rb  # -s = --source, -n = --context-lines
```

**Arguments:**

- `<path>` - File path (relative to project root or absolute)

**Options:**

| Short  | Long                     | Description                                          |
|--------|--------------------------|------------------------------------------------------|
| `-s`   | `--source MODE`          | Include source code (full, uncovered, or none)       |
| `-n`   | `--context-lines N`      | Lines of context around uncovered lines (default: 2) |
| `-C`   | `--color BOOLEAN`        | Enable (`true`)/disable (`false`) coverage marker colors |
| `-f`   | `--format`               | Output format, e.g. `J` (pretty JSON), `j`, `y`, `a`; see [Output Formats](#output-formats) |

**Output (default format):**
```
File: app/controllers/orders_controller.rb
Coverage: 70.00% (7/10 lines)

┌──────┐
│ Line │
├──────┤
│   14 │
│   15 │
│   20 │
└──────┘
```

**Output (JSON format, condensed here; `-fJ` prints it fully indented):**
```json
{
  "schema_version": 1,
  "file": "app/controllers/orders_controller.rb",
  "uncovered_lines": [14, 15, 20],
  "covered": 7, "uncovered": 3, "total": 10, "percentage": 70.0,
  "stale": "ok"
}
```

With `-s`, the JSON also has a `source` array; see [`-s, --source MODE`](#source).

**Output (with source, `-s uncovered` and the default 2 context lines):**
```
File: app/controllers/orders_controller.rb
Coverage: 70.00% (7/10 lines)

┌──────┐
│ Line │
├──────┤
│   14 │
│   15 │
│   20 │
└──────┘

----------+-------------------------------------------------------------
  Line    | Source
----------+-------------------------------------------------------------
    12    |       end
    13    |
    14  X |       def show(id)
    15  X |         @repo.find(id)
    16    |       end
    17    |
    18  ✓ |       def cancel(id)
    19  ✓ |         order = @repo.find(id)
    20  X |         return :missing unless order
    21    |
    22  ✓ |         @repo.cancel(id)
```

**Legend:**

- `✓` - Line is covered
- `X` - Line is not covered
- ` ` - Line is not executable (comments, blank lines)

### `detailed <path>`, `d <path>`

Show per-line coverage with hit counts.

```sh
clp detailed app/models/order.rb
clp d app/models/order.rb
clp -fJ d app/models/order.rb
clp -s full d app/models/order.rb  # -s = --source
```

**Arguments:**

- `<path>` - File path (relative to project root or absolute)

**Options:**

| Short  | Long                     | Description                         |
|--------|--------------------------|-------------------------------------|
| `-f`   | `--format`               | Output format, e.g. `J` (pretty JSON), `j`, `y`, `a`; see [Output Formats](#output-formats) |
| `-s`   | `--source MODE`          | Include source code (full, uncovered, or none) |
| `-n`   | `--context-lines N`      | Lines of context around uncovered lines with `-s uncovered` (default: 2) |
| `-C`   | `--color BOOLEAN`        | Enable (`true`)/disable (`false`) coverage marker colors |

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

**Output (JSON format, condensed here; `-fJ` prints it fully indented):**
```json
{
  "schema_version": 1,
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
  "covered": 6,
  "uncovered": 1,
  "total": 7,
  "percentage": 85.71,
  "stale": "ok"
}
```

### `raw <path>`, `r <path>`

Show the raw SimpleCov lines array.

```sh
clp raw app/models/order.rb
clp r app/models/order.rb
clp -fJ r app/models/order.rb
```

**Arguments:**

- `<path>` - File path (relative to project root or absolute)

**Output (default format):**
```
File: app/models/order.rb

┌──────┬──────────┐
│ Line │ Coverage │
├──────┼──────────┤
│    1 │      nil │
│    2 │      nil │
│    3 │      nil │
│    4 │      nil │
│    5 │      nil │
│    6 │        1 │
│    7 │        1 │
│    8 │        1 │
│    9 │      nil │
│   10 │      nil │
│   11 │        1 │
│   12 │        1 │
│   13 │      nil │
│   14 │      nil │
│   15 │        1 │
│   16 │        0 │
│   17 │      nil │
│   18 │      nil │
│   19 │      nil │
│   20 │      nil │
└──────┴──────────┘
```

**Output (JSON format, condensed here; `-fJ` prints it fully indented):**
```json
{
  "schema_version": 1,
  "file": "app/models/order.rb",
  "lines": [null, null, null, null, null, 1, 1, 1, null, null, 1, 1, null, null, 1, 0, null, null, null, null],
  "stale": "ok"
}
```

**Array explanation:**

- Integer (e.g., `1`, `5`) - Number of times line was executed
- `0` - Line is executable but was not executed
- `null` - Line is not executable (comment, blank line), or excluded from coverage. Lines SimpleCov marked `"ignored"` (excluded with `nocov` blocks or directive comments) are returned as `null` and, like other `null` lines, are not counted in covered or total lines or in percentages.

### `totals`, `t`

Show aggregated totals for the project (or the files matching `--file-globs`).

```sh
clp totals
clp t
clp -fJ t
clp -g "lib/ops/jobs/*.rb" t  # -g = --file-globs
```

`totals` has no table form: `-f table` prints the same text breakdown as the default.

**Output of `clp totals` (default format):**
```
File globs: (none)

Lines (7 ok files): 47 total, 38 covered, 9 uncovered (80.85%)

File breakdown:
  With coverage: 7 total, 7 ok, 0 stale
    Stale: deleted = 0, newer than coverage = 0, line mismatch = 0, unreadable = 0
```

**With `--file-globs` enabled (`clp -g "lib/**/*.rb,app/**/*.rb" t`):**
```
File globs:
  - lib/**/*.rb
  - app/**/*.rb

Lines (7 ok files): 47 total, 38 covered, 9 uncovered (80.85%)

File breakdown:
  With coverage: 7 total, 7 ok, 0 stale
    Stale: deleted = 0, newer than coverage = 0, line mismatch = 0, unreadable = 0
  Without coverage: 3 total
    Not in coverage data = 3, unreadable = 0, skipped (errors) = 0
```

**Output (JSON format):**
```json
{
  "schema_version": 1,
  "covered": 38,
  "uncovered": 9,
  "total": 47,
  "percentage": 80.85,
  "file_globs": [],
  "file_counts": {
    "total": 7,
    "with_coverage": {
      "total": 7,
      "ok": 7,
      "stale": {
        "total": 0,
        "by_type": {
          "deleted": 0,
          "newer": 0,
          "length_mismatch": 0,
          "unreadable": 0
        }
      }
    }
  },
  "timestamp_status": "ok"
}
```

**Notes:**

- The line metrics (`covered`, `uncovered`, `total`, `percentage`) count fresh coverage entries only; `file_counts.with_coverage.ok` is how many files they include, and `file_counts.with_coverage.stale.total` how many stale files they exclude.
- `with_coverage.stale.by_type` keys match the per-file `stale` values: `deleted`, `newer`,
  `length_mismatch`, `unreadable`.
- `without_coverage` is only present when file globs are set.
- Respects `-g` / `--file-globs` when you only want to aggregate a subset of files.
- Totals exclude stale files (`"deleted"`, `"newer"`, `"length_mismatch"`, `"unreadable"`) so the aggregate reflects only fresh coverage data.
- Honors `-S true` / `--raise-on-stale true` to raise if coverage data is out of date.

## Global Options

These options can be used with every subcommand, though some affect only certain subcommands (for example, `-o` affects only `list` and the default report, and `-s`/`-n` only the per-file commands noted below).

Options can come before or after the subcommand, and after it they can be mixed with its arguments. A later value overrides an earlier one, and the command line overrides `COV_LOUPE_OPTS`:

```sh
clp --format json summary lib/api/client.rb
clp summary lib/api/client.rb --format json  # Same result
```

Putting options after the subcommand lets an agent permission rule such as `Bash(cov-loupe list:*)` allow a subcommand with any options; see [CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md#differences-between-the-interfaces).

These options come only before the subcommand; after it they are a usage error: `-m`/`--mode`, `--[no-]allow-code-predicates`, `-h`/`--help`, `-v`/`--version` and `-p`/`--path-for`. Options after an unknown subcommand are not parsed; the unknown subcommand is reported. `validate`'s `-i` goes after `validate`. A standalone `--` before the subcommand is also an error (a `--` that is an option's value, as in `-g --`, is fine).

After the subcommand, an argument that starts with `-` is read as an option, so a path that starts with `-` must follow `--`:

```sh
clp summary -- -odd.rb
```

`-h`/`--help` prints usage and exits, and `-v`/`--version` prints the version and exits; see the [Quick Reference](#quick-reference).

### `-c, --coverage-file PATH`

Path to a SimpleCov `coverage.json` file, or to a directory containing one. With no `-c` argument at all, `coverage/coverage.json` relative to the project root is used.

A relative path is resolved against both the current directory and the project root (`-R`). If it names a valid location under both and the two differ (they are the same when you run from the project root), cov-loupe exits with an ambiguity error; pass an absolute path instead.

For a detailed explanation of how to configure the coverage file location, including the default search path, environment variables, and MCP configuration, see the [Configuring the Coverage File](../../README.md#configuring-the-coverage-file) section in the main README.

### `-R, --root PATH`

Project root directory (default: current directory). The project-level commands warn when most
files in the coverage data are not found under it; see
[Troubleshooting](TROUBLESHOOTING.md#the-project-root-may-be-wrong).

```sh
clp -R /path/to/project  # -R = --root
```

### `-p`, `--path-for NAME`

Print a canonical resource path or URL to stdout and exit immediately.

Supported names:

- `repo` - public GitHub repository URL
- `docs` - public documentation site URL
- `docs-local` - absolute path to local `README.md` (the MCP `help` payload names this resource `docs_local`)

```sh
clp -p repo
clp --path-for repo
clp --path-for docs
clp --path-for docs-local
```

An unknown name is a usage error (exit 2) that lists the valid names.

This option is designed for shell composition and prints only the value:

```sh
open "$(clp --path-for docs)"
```

### `-f, --format FORMAT`

Selects the output format. Short codes are case-sensitive.

| Short | Long            | Description                        |
|-------|-----------------|------------------------------------|
| `a`   | `amazing_print` | AmazingPrint-formatted Ruby object |
| `i`   | `inspect`       | Ruby `#inspect` output             |
| `j`   | `json`          | Single-line, compact JSON          |
| `J`   | `pretty_json`   | Multi-line, indented JSON          |
| `p`   | `puts`          | Ruby `Kernel#puts` output          |
| `P`   | `pretty_print`  | Ruby stdlib `PP.pp` output         |
| `t`   | `table`         | Formatted table (Unicode or ASCII) |
| `y`   | `yaml`          | YAML                               |

```sh
clp -fJ summary lib/api/client.rb   # multi-line, indented JSON
clp -fj summary lib/api/client.rb   # single-line JSON
```

JSON output (`-fj` / `-fJ`) is useful for:

- Parsing in scripts
- Integration with other tools
- Machine consumption

### `-o, --sort-order ORDER`

Sort order for `list`, including the default report when no subcommand is given.

**Values:**

- `descending`, `d` - Highest coverage first (default)
- `ascending`, `a` - Lowest coverage first

```sh
clp -o d list  # d = descending (default)
clp -o a list  # a = ascending
```

<a id="source"></a>

### `-s, --source MODE`

Include source code in output (default: no source). Applies to `summary`, `uncovered`, and `detailed`; `raw` ignores it. Source files are read as UTF-8 whatever the locale. For a file that is not valid UTF-8, JSON and YAML output fail with `Source file is not valid UTF-8`, the table shows the bytes raw, and the other formats escape them; convert such files to UTF-8.

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

With a structured format (`-fJ`, `-f yaml`, etc.), the source is returned as a `source` array instead of annotated text; each entry has `line`, `code`, `hits`, and `covered` (`hits` and `covered` are `null` for non-executable lines).

### `-n, --context-lines N`

Number of context lines around uncovered code (for `-s uncovered` / `--source uncovered`). Must be a non-negative integer.

```sh
clp -s u -n 3 uncovered lib/api/client.rb  # -s u = uncovered, -n = --context-lines
```

**Default:** 2 lines

### Boolean Flags (`--color` / `-C`, `--raise-on-stale`)

These options require explicit boolean values. Recognized literals (case-insensitive):

| True   | False   |
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

Enable or disable ANSI colors for the coverage markers in source output. Requires an explicit boolean value.

```sh
clp -s uncovered --color true uncovered lib/api/client.rb
clp -s uncovered -C false uncovered lib/api/client.rb
```

**Default:** Colors enabled if output is a TTY

### `-S, --raise-on-stale BOOLEAN`

Raise error if coverage is stale. Project queries (`list`, `totals`, the default report, and `validate` predicates that call `model.list` or `model.project_totals`) also raise if a file matching the file globs is not in coverage data or a coverage row is skipped because its data is invalid. Requires an explicit boolean value. Default is `false` (report staleness and skipped rows instead of raising; `totals` counts skipped rows only when file globs are set, and otherwise leaves them out of its output, logging each only as an INFO line).

```sh
# Enable raising an error if coverage is stale
clp -S true
clp --raise-on-stale yes

# Explicitly disable raising an error (useful to override COV_LOUPE_OPTS)
clp --raise-on-stale false
```

**Staleness conditions:**

- **"deleted"** (Deleted): Source file no longer exists on disk
- **"newer"** (Timestamp): Source file modified after coverage was generated
- **"length_mismatch"** (Length): Source file line count differs from coverage data
- **"unreadable"** (Unreadable): Source file could not be read (permission or I/O errors), or its staleness check failed
- Files matching the file globs that are not in coverage data (with `--file-globs`; checked by `list`, `totals`, the default report, and `validate` predicates that call `model.list` or `model.project_totals`; the per-file commands ignore `-g`)

<a id="file-globs"></a>

### `-g, --file-globs PATTERNS`

Comma-separated glob patterns. They limit results to matching files, and report matching files on disk that have no coverage data at all.

- Put all patterns in one `-g` value; a repeated `-g` replaces the earlier one.
- The value is split only on commas outside `{...}` and `[...]`, so brace alternatives and character classes stay whole: `-g 'app/{models,controllers}/**/*.rb,lib/**/*.rb'` is two patterns. To write a literal comma in a pattern, use `[,]`, which works everywhere. A comma escaped with a backslash (`\,`) also does not split, except on Windows, where a backslash is a path separator. A doubled backslash (`\\`) is an escaped backslash, so a comma after it does split. The backslash must reach cov-loupe, so quote it (`-g 'a\,b.rb,c.rb'`): Unix shells and `COV_LOUPE_OPTS` both remove an unquoted backslash. In `COV_LOUPE_OPTS` the quotes go inside the value: `COV_LOUPE_OPTS="-g 'a\,b.rb,c.rb'"`. Empty items, as in `'a,,b'` or a trailing comma, are ignored, so a value with no patterns at all, such as `''` or `','`, means no file globs. One contrived case is not followed: a `[` that opens inside braces and closes after them, as in `{a[1,2},b]`, is split at the comma after `}`, giving `{a[1,2}` and `b]`.
- An unclosed `{`, or an unclosed `[` outside braces, is a usage error (exit 2) for every command, including the per-file ones that otherwise ignore `-g`, and at MCP server startup. A bad value in `COV_LOUPE_OPTS` is parsed before the command line, so it fails every command even when the command line passes its own `-g`; see [`COV_LOUPE_OPTS`](#cov_loupe_opts) for how such errors are reported. CRuby matches no files for such a pattern; JRuby reads an unmatched `{` literally, but it is rejected there too, so a value means the same on every engine. To match a literal `[`, write `[[]` (or `\[`, except on Windows). To match a literal `{`, escape it as `\{`, quoted like `\,` above so the backslash reaches cov-loupe; on Windows, where a backslash is a path separator, a literal `{` cannot be written in `-g`. See [Advanced Filtering](ADVANCED_USAGE.md#advanced-filtering-glob-patterns).

**Default:** `[]` (empty - shows every file in the coverage file)

**Why no default patterns?**

1. **Transparency** - Shows all coverage data without hiding files that don't match assumptions
2. **Avoids false positives** - Broad patterns like `**/*.rb` flag migrations, bin scripts, etc. as "missing"
3. **Project variety** - Coverage patterns vary by project structure (lib/, app/, src/, config/, etc.)

**Important:** Files that are not in the coverage file are not visible with the default empty array. That includes files added since the last test run, and files never loaded during tests unless SimpleCov's `cover` globs include them (SimpleCov then records them at 0%).

**When to set it:** leave it unset to see what SimpleCov reported. Set it to also catch files with no coverage data. Use patterns that describe the files you expect to be covered, normally the globs you give SimpleCov's `cover`, so files outside them are not reported as missing. Files that SimpleCov's `skip` filters remove still match the globs, though, and are reported as missing; narrow the globs to leave them out. For example, with this SimpleCov setup, set the matching globs in `COV_LOUPE_OPTS` so every project-level command uses them:

```ruby
# In spec_helper.rb or similar
SimpleCov.start do
  skip '/spec/'
  skip '/test/'
  cover 'lib/**/*.rb', 'app/**/*.rb'
end
```

```sh
# In your shell config (.bashrc, .zshrc, etc.)
# Match the cover patterns above
export COV_LOUPE_OPTS="--file-globs lib/**/*.rb,app/**/*.rb"
```

**Usage:**

```sh
# Use environment variable for project-wide default
export COV_LOUPE_OPTS="--file-globs lib/**/*.rb,app/**/*.rb"
clp list  # Uses globs from env var

# Or specify per-command
clp -g "lib/api/**/*.rb" list

# Multiple patterns
clp -g "lib/**/*.rb,app/models/**/*.rb" list

# Export for CI (with globs to match SimpleCov)
clp -g "lib/**/*.rb,app/**/*.rb" -fJ list > coverage-report.json
```

**Use cases:**

- **Limit results** - Narrow focus to a subsystem or layer
- **Include files without coverage** - Report files that should have coverage but aren't in the coverage file
- **CI validation** - Use with `-S true`/`--raise-on-stale true` to catch coverage gaps

**Important:** The `not_in_coverage_files` array (in `list` output) only includes files that:

1. Match the file globs
2. Exist in the filesystem
3. Are NOT in the coverage file

Without globs, this array is empty (no expectations = no violations).

### `-l, --log-file PATH`

Log target. The default is `stderr`; use a file path for persistent logging.
Use 'stderr' to log to standard error.
Use 'off' to disable logging entirely (cross-platform alternative to /dev/null); use './off' for a file named `off`.
Logging to 'stdout' is not permitted because it would corrupt command output.
A relative log file path is resolved against the current directory, not `--root`.

With the default `stderr` target, the CLI does not log its parameters or errors there;
an error appears there once, as the user-facing message (followed by its stack trace
with `--error-mode debug`). Warnings and diagnostics about the coverage data can still
appear on stderr. A file target also receives a `CLI parameters` line for each run whose
options are valid and whose subcommand, if any, is known and, unless `--error-mode off`
is used, a log entry for each error. Invalid options and option values are rejected
before logging is set up, so they appear only on stderr; an unknown subcommand and other
usage errors found by the subcommand, such as a missing path, are logged to the file.

```sh
clp -l /tmp/cov-loupe.log  # -l = --log-file
clp -l stderr                   # Log to standard error
clp -l off                      # Disable logging entirely
```

**Default:** `stderr` — see the [logging initialization and target testing guide](LOGGING.md#log-file-initialization-and-target-testing).

**Warning:** Explicit log files may grow unbounded in long-running or CI usage. cov-loupe does not rotate them; use external rotation or periodically clean them up. If multiple agents or processes run concurrently, give each one a different log file; see [Concurrent processes and agents](LOGGING.md#concurrent-processes-and-agents).

### `-e, --error-mode MODE`

Error handling verbosity.

**Modes:**

| Value abbreviation | Long    | Description                               |
|--------------------|---------|-------------------------------------------|
| `o`                | `off`   | No error logging                          |
| `l`                | `log`   | Log errors without stack traces (default) |
| `d`                | `debug` | Log errors with full stack traces         |

Error messages are always printed to stderr, and `debug` also prints a stack trace
after the message: the first 5 lines with a log file, which gets the full trace, and
otherwise (the default `stderr` target, or `off`) the full trace. With the `stderr` target, errors are
not logged there a second time, so `off` and `log` look the same. With a log file,
`log` and `debug` write each error to the file.

```sh
clp --error-mode debug summary lib/api/client.rb
clp -e debug summary lib/api/client.rb  # -e = --error-mode
clp -edebug summary lib/api/client.rb   # attached short option form
```

<a id="output-chars"></a>

### `-O, --output-chars MODE`

Choose how cov-loupe draws its own decoration (table borders and the covered-line marker): with Unicode characters, or with ASCII for terminals that cannot display them. Your data is never changed.

**Modes:**

| Short | Long        | Description                                       |
|-------|-------------|---------------------------------------------------|
| `d`   | `default`   | UTF-8 output encoding → Unicode, else ASCII (default) |
| `f`   | `fancy`     | Draw tables and markers with Unicode characters   |
| `a`   | `ascii`     | Draw tables and markers with ASCII characters     |

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

**What changes in ASCII mode:**

- Table borders (│ ─ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ become | - + + + + + + + + +)
- The covered-line marker in source output (✓ becomes +; the uncovered marker is always `X`)
- JSON output (`-f json`, `-f pretty_json`) escapes non-ASCII characters as `\uXXXX`. This
  encodes the data without changing it: parsing the JSON gives back the original text.

**What never changes:**

- Your data: file paths, source lines, error messages, backtraces, and YAML or other text
  formats are shown exactly as they are, so output in ASCII mode can still contain non-ASCII
  characters such as accented letters, curly quotes, or Japanese
- Log files

cov-loupe never rewrites data for display. Ruby itself escapes non-ASCII characters as
`\uXXXX` in the `inspect`, `pretty_print`, `amazing_print` and `puts` formats, and in error
messages that quote a path the way `inspect` does, when Ruby's default encodings are not UTF-8.
Under the C locale (`LANG=C`) the `cov-loupe` executable sets `Encoding.default_external` to
UTF-8, so the characters are shown as they are there (unless `Encoding.default_internal` is
set to a non-UTF-8 encoding, for example with `RUBYOPT=-E:US-ASCII`; then the other formats
can fail to write non-ASCII characters at all).

**Use cases:**

- **CI/CD systems** whose logs or terminals cannot draw box-drawing characters: `clp -O ascii list`
- **Windows** with a legacy code page, so table borders render: `clp -O ascii summary lib/api/client.rb`
- **Piped output** to files that should not contain box-drawing characters: `clp -O ascii list > coverage.txt`
- **Force Unicode** when the locale is not UTF-8 but the terminal can draw it: `clp -O fancy list`

**Note:** The default mode checks the output encoding, which normally follows your locale (e.g., `LANG`): UTF-8 gives Unicode, anything else ASCII. It cannot see what your terminal can actually draw. If table borders or the ✓ marker appear garbled, try `clp -O ascii`. Non-ASCII characters in your data are left as they are in every mode, except that ASCII mode escapes them as `\uXXXX` in JSON output.

**Limitation:** Table column widths are measured in characters, so wide (for example CJK) characters can leave the right border misaligned.

### `-m, --mode MODE`

Specify execution mode: `cli` or `mcp` (or `c`/`m`; default: `cli`). Use `--mode mcp` to run as an MCP server.
cov-loupe never switches to MCP mode on its own; without `--mode mcp` (on the command line or in `COV_LOUPE_OPTS`) it runs in CLI mode.

```sh
clp -m mcp               # MCP server mode (required for MCP), short option form
clp --mode mcp           # MCP server mode (required for MCP), long option form
clp -m cli list          # CLI mode (default), can use to override environment variable
```

### `--[no-]allow-code-predicates`

MCP mode only: registers the `project_validate` tool, which runs Ruby predicates supplied by the MCP client with full process privileges. Off by default. The CLI `validate` subcommand does not need it, and CLI mode ignores the option, so it can be set in a `COV_LOUPE_OPTS` shared by both modes. See [MCP Integration: Policy Validation Tools](MCP_INTEGRATION.md#policy-validation-tools).

```sh
clp -m mcp --allow-code-predicates     # enable project_validate
clp -m mcp --no-allow-code-predicates  # disable it, overriding COV_LOUPE_OPTS
```

### `validate <file> | -i <code>`, `v <file> | -i <code>` (`-i` = `--inline`)

Validate coverage against custom policies for CI/CD enforcement.

> **⚠️ SECURITY WARNING**
>
> Validation predicates execute as **arbitrary Ruby code with full system privileges**. They have unrestricted access
> to file system, network, system commands, and environment variables.
>
> **Only use predicate files from trusted sources.**
> Review predicates before use, especially in CI/CD environments.

The predicate must be a callable (lambda, proc, or object with `#call` method) that receives a `CoverageModel` and returns a truthy or falsy value; this applies to `-i` code too, so `-i 'true'` is an error. A predicate file path is resolved against the current directory, not `--root`, and the file is read as UTF-8 whatever the locale.

**Predicate return values:**

- Truthy (e.g., `true`) - Coverage meets your criteria (CLI exits with code 0)
- Falsy (`false` or `nil`) - Coverage fails your criteria (CLI exits with code 3)
- Error in the predicate itself (syntax error, not callable, or an exception raised by its own code) - Predicate error (CLI exits with code 4). Coverage-data errors triggered while the predicate queries the model, such as a missing file or stale data with `--raise-on-stale true`, exit with code 1 like any other command.

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
clp validate -i '->(m) { m.list["files"].all? { |f| f["percentage"].nil? || f["percentage"] >= 80 } }'
clp v -i '->(m) { m.list["files"].all? { |f| f["percentage"].nil? || f["percentage"] >= 80 } }'

# Long form of -i, with an option after the subcommand
clp validate --inline '->(m) { m.list["files"].size > 0 }' -S true
clp v --inline '->(m) { m.list["files"].size > 0 }' -S true
```

**Example predicate file:**
```ruby
# coverage_policy.rb
->(model) do
  model.list["files"].all? { |f| f['percentage'].nil? || f['percentage'] >= 80 }
end
```

See [examples/success_predicates/](../../examples/success_predicates/README.md) for more examples.

## Output Formats

### Table Format

The default format, except for `totals`, which has no table form, and `validate`, which prints no result. Uses Unicode box-drawing characters, or ASCII when the output encoding is not UTF-8 or with `-O ascii` (see [`--output-chars`](#output-chars)).

```
┌──────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                             │        % │   Covered │   Total │ Stale │
├──────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ lib/payments/refund_service.rb   │   60.00% │         3 │       5 │       │
└──────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
```

### JSON Format

Machine-readable output. Paths of files under the project root are relative to it; files outside the root keep absolute paths.
Every structured CLI format and library coverage hash has integer `schema_version` as its first key. The [shipped JSON Schemas](https://github.com/keithrbennett/cov-loupe/tree/main/lib/cov_loupe/schemas/v1) define these shapes; see [Schema Version](LIBRARY_API.md#schema-version) for schema lookup and compatibility rules.

```json
{
  "schema_version": 1,
  "file": "app/models/order.rb",
  "covered": 6,
  "uncovered": 1,
  "total": 7,
  "percentage": 85.71,
  "stale": "ok"
}
```

**Staleness values:**

- `"ok"` - Coverage data is current
- `"deleted"` - Source file deleted (no longer exists on disk)
- `"newer"` - Timestamp mismatch (file modified after coverage)
- `"length_mismatch"` - Length mismatch (line count differs)
- `"unreadable"` - Source file could not be read, or its staleness check failed

## Environment Variables

### `COV_LOUPE_OPTS`

Default command-line options applied to all invocations.

**Format:** Shell-style string containing CLI options only: no subcommand, arguments, `--`, or `validate`'s `-i`

```sh
export COV_LOUPE_OPTS="--raise-on-stale true -fJ"
clp summary lib/api/client.rb  # Automatically uses options above
```

**Precedence:** Command-line arguments override environment options

```sh
# Environment sets -fJ; explicit CLI options still take precedence
export COV_LOUPE_OPTS="-fJ"
clp summary lib/api/client.rb  # Uses JSON (from env)
clp -f table summary lib/api/client.rb  # Explicit override to table format
```

**Parsing:** `COV_LOUPE_OPTS` is parsed on its own, before the command line, into the same settings, so it must be complete: an option at its end that needs a value is an error there, rather than taking the first command-line argument. An option that fails to parse in `COV_LOUPE_OPTS` fails every command, even one that passes the same option correctly. A setting that is invalid only as a final value, such as `--log-file stdout`, can be overridden on the command line. A word in `COV_LOUPE_OPTS` that is not an option (such as a subcommand), or a standalone `--`, is a usage error; see [Migrating to v7](migrations/MIGRATING_TO_V7.md#options-can-follow-the-subcommand).

**Errors:** an option's error message does not say whether the option came from `COV_LOUPE_OPTS` or the command line. When it is in `COV_LOUPE_OPTS` (an option or value there fails to parse, or a final setting is invalid because of it), the error is followed by a line saying so, with the value:

```text
Error: Unclosed '[' in --file-globs value: "lib/[ab". To match a literal '[', write '[[]'
The error is in COV_LOUPE_OPTS ("-g 'lib/[ab'"), which is read before the command line.
Run 'cov-loupe --help' for usage information.
```

A `COV_LOUPE_OPTS` that cannot be split into arguments, such as one with an unclosed quote, gets no such line, because its message already names it (`Error: Invalid COV_LOUPE_OPTS format: ...`). Errors in the command line get no such line either, unless `COV_LOUPE_OPTS` has the same error, as when both set `--log-file stdout`. Neither do errors found after the options are parsed, such as a `-c` path that does not exist or an unknown subcommand, even when a value from `COV_LOUPE_OPTS` caused them.

**Examples:**
```sh
# Default coverage file location
export COV_LOUPE_OPTS="-c build/coverage"

# Enable detailed error logging
export COV_LOUPE_OPTS="--error-mode debug"

# Paths with spaces
export COV_LOUPE_OPTS='-c "/path with spaces/coverage"'

# Multiple options
export COV_LOUPE_OPTS="-S true -fJ --error-mode debug"
```



## Examples

### Basic Coverage Check

```sh
# Show all files sorted by highest coverage first (default)
clp

# Find the 5 files with worst coverage (the first 3 lines are the table's top border, header, and separator)
clp -o a list | head -8
```

### Detailed File Investigation

```sh
# Check a specific file
clp summary lib/payments/refund_service.rb

# See which lines aren't covered
clp uncovered lib/payments/refund_service.rb

# View uncovered code in context
clp -s uncovered -n 3 uncovered lib/payments/refund_service.rb

# Get detailed hit counts
clp detailed lib/payments/refund_service.rb
```

### JSON Output for Scripts

The rexe examples use [rexe](https://github.com/keithrbennett/rexe) (`gem install rexe`), whose `-ij -mb` options parse JSON input into `self`.

```sh
# Get JSON for parsing
clp -fJ list > coverage-report.json

# Extract files below threshold
clp -fJ list | jq '.files[] | select(.percentage != null and .percentage < 80)'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].select { |f| f["percentage"] && f["percentage"] < 80 }.each do |f|
    puts JSON.pretty_generate(f)
  end
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ 'self["files"].select { |f| f["percentage"] && f["percentage"] < 80 }'

# Count files below 80% coverage
clp -fJ list | jq '[.files[] | select(.percentage != null and .percentage < 80)] | length'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  puts JSON.parse($stdin.read)["files"].count { |f| f["percentage"] && f["percentage"] < 80 }
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -op 'self["files"].count { |f| f["percentage"] && f["percentage"] < 80 }'
```

### Filtering and Sorting

```sh
# Show only lib/ files
clp -g "lib/**/*.rb" list

# Show files sorted by highest coverage
clp -o d list

# Show the worst-covered files first
clp -o a list

# Check specific directory
clp -g "lib/payments/**/*.rb" list
```



### Staleness Checking

```sh
# Check if coverage is stale (for CI/CD)
clp -S true

# Check with specific file patterns. On the demo fixture this exits 1: two files
# these globs match are not in coverage data, which -S true also treats as stale
clp -S true -g "lib/payments/**/*.rb,lib/ops/jobs/**/*.rb" list

# See which files are stale (don't error)
clp list  # Stale column shows deleted/newer/length_mismatch/unreadable markers
```

### Source Code Display

```sh
# Show full source with coverage markers
clp -s full summary lib/api/client.rb

# Show only uncovered lines with context
clp -s uncovered uncovered lib/api/client.rb

# More context around uncovered code
clp -s uncovered -n 5 uncovered lib/api/client.rb

# Without colors (for logging)
clp -s full --color false uncovered lib/api/client.rb
```

### CI/CD Integration

```sh
# Fail build if coverage is stale
clp -S true || exit 1

# Generate JSON report for artifact
mkdir -p artifacts
clp -fJ list > artifacts/coverage-report.json

# Check specific directory in monorepo
cov-loupe -R services/api -c services/api/coverage  # -R = --root, -c = --coverage-file
```

### Debugging

```sh
# Verbose error output
clp --error-mode debug summary lib/api/client.rb

# Custom log file (--log-file or -l)
clp -l /tmp/cov-loupe-debug.log summary lib/api/client.rb
```

## Exit Codes

- `0` - Success
- `1` - Error (file not found, coverage data missing, stale coverage with `-S true` / `--raise-on-stale true`, etc.)
- `2` - Usage error (invalid option, option value, or subcommand arguments, including an argument that is not valid text in its encoding; invalid configuration such as `--log-file stdout`)
- `3` - Validation failed: the `validate` predicate ran and returned a falsy value
- `4` - Predicate error: the `validate` predicate itself could not be loaded or raised an error (coverage-data errors it triggers exit `1`)

## Next Steps

- **[Library API](LIBRARY_API.md)** - Use in Ruby code
- **[Examples](EXAMPLES.md)** - More usage examples and recipes
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
