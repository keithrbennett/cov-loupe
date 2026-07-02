# Migrating to v6.0

[Back to Migration Guides](README.md)

This document describes the breaking changes introduced in version 6.0.0.

## Table of Contents

- [Stdout Logging Is No Longer Permitted](#stdout-logging-is-no-longer-permitted)
- [Format Short Codes and Long Names Normalized](#format-short-codes-and-long-names-normalized)

---

## Stdout Logging Is No Longer Permitted {#stdout-logging-is-no-longer-permitted}

Logging to `stdout` is no longer allowed. The `--log-file` / `-l` option rejects `stdout` in all modes (CLI, MCP, and library use). Logs are diagnostics and must not be written to the same stream as command output.

**Rationale:**

- In CLI mode, `stdout` is reserved for coverage tables, JSON, YAML, and other command output. Interleaving diagnostic logs with that output breaks pipelines and scripts that parse the data.
- In MCP mode, `stdout` carries the JSON-RPC protocol stream. Any non-protocol output corrupts the connection.

**Before (v5.x):**

```sh
# Allowed in CLI mode, rejected only in MCP mode
cov-loupe --log-file stdout list
cov-loupe --log-file stdout summary lib/foo.rb
```

**After (v6.0):**

```sh
# Use stderr instead
cov-loupe --log-file stderr list
cov-loupe --log-file stderr summary lib/foo.rb

# Or log to a file (default is ./cov_loupe.log)
cov-loupe --log-file /var/log/cov-loupe.log list

# Or disable logging entirely
cov-loupe --log-file :off list
```

**Migration:**

- Replace every `--log-file stdout` or `-l stdout` with `--log-file stderr`, a file path, or `:off`.
- Update any `COV_LOUPE_OPTS` environment variable that sets `--log-file stdout`.
- Update programmatic configuration that sets `CovLoupe.default_log_file = 'stdout'` or `CovLoupe.active_log_file = 'stdout'`.

Attempting to use `stdout` now raises `CovLoupe::ConfigurationError` during normal configuration validation:

```text
Logging to stdout is not permitted because it corrupts command output. Use 'stderr', a file path, or ':off' to disable logging.
```

Note: `--help`, `--version`, and `--path-for` exit before configuration validation runs, so an invalid `--log-file stdout` on those flags alone will not surface this error.

## Format Short Codes and Long Names Normalized {#format-short-codes-and-long-names-normalized}

The `--format` / `-f` option (CLI) and the `format` parameter (MCP `project_coverage` tool) now use exactly one canonical short code and one canonical long name per format. Noncanonical aliases are no longer accepted, and two formats were added.

**Canonical formats:**

| Short | Long             |
|-------|------------------|
| `a`   | `amazing_print`  |
| `i`   | `inspect`        |
| `j`   | `json`           |
| `J`   | `pretty_json`    |
| `p`   | `puts`           |
| `P`   | `pretty_print`   |
| `t`   | `table`          |
| `y`   | `yaml`           |

**Rationale:**

- A single short code and a single long name per format removes ambiguity and lets both cov-loupe and related tools (e.g. `wifiwand`) share one option scheme.
- `puts` and `pretty_print` were added as thin wrappers around Ruby's own `Kernel#puts` and stdlib `PP.pp`, useful when inspecting data the way it would appear in an interactive Ruby session. `inspect` returns the raw `#inspect` string.

**Before (v5.x):**

```sh
cov-loupe -fp list                    # 'p' meant pretty_json
cov-loupe --format pretty-json list   # 'pretty-json' was accepted
cov-loupe -f ap list                  # 'ap' meant amazing_print
cov-loupe --format awesome_print list # 'awesome_print' was accepted
```

**After (v6.0):**

```sh
cov-loupe -fJ list                    # 'J' now means pretty_json
cov-loupe --format pretty_json list   # only 'pretty_json' is accepted
cov-loupe -f a list                   # only 'a' means amazing_print
cov-loupe --format amazing_print list # only 'amazing_print' is accepted

# New formats
cov-loupe -f i list                   # inspect: Ruby #inspect output
cov-loupe -fp list                    # puts: Ruby Kernel#puts output ('p' now means puts, not pretty_json)
cov-loupe -f P list                   # pretty_print: Ruby stdlib PP.pp output
```

**Migration:**

- Replace `-fp` / `--format pretty_json` / `--format pretty-json` used for pretty JSON with `-fJ` / `--format pretty_json`.
- Replace `-f ap` / `--format awesome_print` / `--format ap` with `-f a` / `--format amazing_print`.
- Any script or `COV_LOUPE_OPTS` value relying on `-fp` meaning pretty JSON must be updated, since `-fp` now means `puts`.
- MCP clients passing `"format": "p"` or `"format": "pretty-json"` to `project_coverage` must switch to `"format": "J"` or `"format": "pretty_json"`.
