# Migrating to v6.0

[Back to Migration Guides](README.md)

This document describes the breaking changes introduced in version 6.0.0.

## Table of Contents

- [Stdout Logging Is No Longer Permitted](#stdout-logging-is-no-longer-permitted)

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
