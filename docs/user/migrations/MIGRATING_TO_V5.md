# Migrating to v5.0

[Back to Migration Guides](README.md)

This document describes the breaking changes introduced in version 5.0.0.

## Table of Contents

- [MCP Tool Names Renamed](#mcp-tool-names-renamed)
- [Removed `version` Subcommand](#removed-version-subcommand)
- [Simplified `--version` Output](#simplified-version-output)
- [Single-Letter Subcommand Abbreviations](#single-letter-subcommand-abbreviations)
- [Totals Key Renamed: `percent_covered` → `percentage`](#totals-key-renamed)

---

## MCP Tool Names Renamed

All MCP tool names have the `_tool` suffix removed. File-scope tools gain a `file_` prefix and
project-scope tools gain a `project_` prefix. The meta-tools (`help`, `version`) are simply
shortened from `help_tool` and `version_tool`.

| v4.x name                | v5.0 name                 |
|--------------------------|---------------------------|
| `coverage_summary_tool`  | `file_coverage_summary`   |
| `coverage_detailed_tool` | `file_coverage_detailed`  |
| `coverage_raw_tool`      | `file_coverage_raw`       |
| `uncovered_lines_tool`   | `file_uncovered_lines`    |
| `list_tool`              | `project_coverage`        |
| `coverage_totals_tool`   | `project_coverage_totals` |
| `coverage_table_tool`    | `project_coverage` (format: table) |
| `validate_tool`          | `project_validate`        |
| `help_tool`              | `help`                   |
| `version_tool`           | `version`                |

Update any MCP client configurations, tool-call strings in prompts, or direct JSON-RPC requests
that reference the old names.

---

## Removed `version` Subcommand

The `version` subcommand has been removed. Any scripts calling `cov-loupe version` must be updated.

**Before (v4.x):**
```sh
cov-loupe version
cov-loupe --format json version
```

**After (v5.0):**
```sh
cov-loupe --version   # or: cov-loupe -v
```

---

## Simplified `--version` Output {#simplified-version-output}

`-v`/`--version` now prints only the bare version string and exits immediately.
 The former table output (with `Gem Root` and `Documentation` fields) and JSON format option are gone.

**Before (v4.x):**
```
┌───────────────┬────────────────────────────────────────┐
│ Version       │ 4.1.0                                  │
│ Gem Root      │ /path/to/gem                           │
│ Documentation │ README.md and docs/user/**/*.md …      │
└───────────────┴────────────────────────────────────────┘
```

**After (v5.0):**
```
5.0.0
```

If you need the gem root path, use `cov-loupe --path-for docs-local` to locate the local documentation, or inspect the gem installation with `gem contents cov-loupe`.

---

## Single-Letter Subcommand Abbreviations

All CLI subcommands can now be abbreviated to their first letter for convenience.

**Before (v4.x):**
```sh
cov-loupe list
cov-loupe summary lib/foo.rb
cov-loupe uncovered lib/foo.rb
cov-loupe validate -i '->(m) { m.list["files"].all? { |f| f["percentage"] >= 80 } }'
```

**After (v5.0):**
```sh
cov-loupe l
cov-loupe s lib/foo.rb
cov-loupe u lib/foo.rb
cov-loupe v -i '->(m) { m.list["files"].all? { |f| f["percentage"] >= 80 } }'
```

Available abbreviations: `l` (list), `s` (summary), `r` (raw), `u` (uncovered), `d` (detailed), `t` (totals), `v` (validate).

---

## Totals Key Renamed: `percent_covered` → `percentage` {#totals-key-renamed}

The `lines` hash returned by `project_totals`
 (and all outputs that delegate to it: the `totals`
CLI subcommand in JSON/YAML/pretty-json format, and the `project_coverage_totals` MCP tool) now
uses `"percentage"` instead of `"percent_covered"`. This makes aggregated totals consistent with
the per-file summary API, which already used `"percentage"`.

**Before (v4.x):**
```ruby
totals = model.project_totals
totals['lines']['percent_covered']  # => 81.3
```
```json
{ "lines": { "total": 123, "covered": 100, "uncovered": 23, "percent_covered": 81.3 } }
```

**After (v5.0):**
```ruby
totals = model.project_totals
totals['lines']['percentage']  # => 81.3
```
```json
{ "lines": { "total": 123, "covered": 100, "uncovered": 23, "percentage": 81.3 } }
```

**Migration:**
- Replace `totals['lines']['percent_covered']` with `totals['lines']['percentage']`.
- Update `jq` snippets: `.lines.percent_covered` → `.lines.percentage`.
- Update inline predicates passed to `validate -i`: replace `"lines"]["percent_covered"]` with `"lines"]["percentage"]`.

No alias key is provided. The value and rounding are unchanged; only the key name differs.
