# V3.0 Breaking Changes Guide

[Back to main README](../../../README.md)

This document describes the breaking changes introduced in version 3.0.0, which primarily involve the renaming of the gem from `simplecov-mcp` to `cov-loupe`. These changes affect the gem name, executable, Ruby API, and configuration.

---

## What Changed

The project has been completely renamed, impacting various aspects:

### Gem & Executable
*   **Gem name**: `simplecov-mcp` → `cov-loupe`
*   **Executable**: `simplecov-mcp` → `cov-loupe`
*   **Repository**: `github.com/keithrbennett/simplecov-mcp` → `github.com/keithrbennett/cov-loupe`

### Ruby API
*   **Module Name**: `SimpleCovMcp` → `CovLoupe`
*   **Require Path**: `require 'simplecov_mcp'` → `require 'cov_loupe'`

### Configuration
*   **Environment variable**: `SIMPLECOV_MCP_OPTS` → `COV_LOUPE_OPTS`
*   **Log file**: `simplecov_mcp.log` → `cov_loupe.log`
*   **Documentation alias**: `smcp` → `clp`

## What Stayed the Same

*   **Core functionality**: No breaking changes to features, CLI command logic (other than the executable name), or the internal structure of the `CoverageModel` logic.
*   **MCP Protocol**: The JSON-RPC tool definitions and behaviors remain consistent.

## Migration Steps

To upgrade from `simplecov-mcp` (v2.x) to `cov-loupe` (v3.x), follow these steps:

1.  **Uninstall the old gem**:
    ```bash
    gem uninstall simplecov-mcp
    ```

2.  **Install the new gem**:
    ```bash
    gem install cov-loupe
    ```

3.  **Update scripts and aliases**:
    *   Change all occurrences of the `simplecov-mcp` command to `cov-loupe` in your shell scripts, CI/CD configurations, and shell aliases.

4.  **Update Ruby code**:
    *   Find: `require 'simplecov_mcp'`
    *   Replace with: `require 'cov_loupe'`
    *   Find: `SimpleCovMcp`
    *   Replace with: `CovLoupe`

5.  **Update environment variables**:
    *   Rename any `SIMPLECOV_MCP_OPTS` environment variables to `COV_LOUPE_OPTS`.

6.  **Update log file references**:
    *   If you rely on the default log file, it will now be named `cov_loupe.log`. Update any scripts or tools that reference `simplecov_mcp.log`.

**Note**: The old `simplecov-mcp` gem (v2.0.1) will remain available on RubyGems but will not receive further updates.

---

## Getting Help

If you encounter issues migrating to v3.0:

1.  Check the [Troubleshooting](../TROUBLESHOOTING.md) guide.
2.  Review the [CLI Usage](../CLI_USAGE.md) for complete CLI reference.
3.  See [MCP Integration](../MCP_INTEGRATION.md) for MCP tool documentation.
4.  Open an issue at https://github.com/keithrbennett/cov-loupe/issues.
