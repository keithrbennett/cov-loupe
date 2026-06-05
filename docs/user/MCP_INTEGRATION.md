# MCP Integration Guide

[Back to main README](../index.md)

> **⚠️ BREAKING CHANGE (v4.0.0+):** The `-m/--mode mcp` flag is now **required** to run cov-loupe as an MCP server. 
> Automatic mode detection based on TTY/stdin has been removed. If you're upgrading from an earlier version, you **must** update your MCP server configuration to include `-m mcp` or `--mode mcp` or the server will run in CLI mode and hang. See [Migration Guide](migrations/MIGRATING_TO_V4.md) for details.

## Table of Contents

- [Setup by Client](#setup-by-client)
    - [Claude Code](#claude-code)
    - [Codex](#codex)
    - [Gemini](#gemini)
    - [Kilo](#kilo)
- [Stdout Must Stay Clean During MCP Startup](#stdout-must-stay-clean-during-mcp-startup)
- [Available MCP Tools](#available-mcp-tools-functions)
- [Testing Your Setup](#testing-your-setup)
- [Troubleshooting](#troubleshooting)

## Setup by Client

> **Note:** MCP tools and their configuration methods evolve rapidly. The commands and approaches listed below may have changed by the time you read this. Check your client's documentation (e.g., `claude mcp --help`, `codex mcp --help`) for the most current instructions.

### Claude Code

`mcp add` expects first the display name, then the executable (filename or path). The executable's filename is sufficient if it is in the PATH, but you may also specify the fully qualified path if necessary (e.g. `/a/b/cov-loupe`).

```sh
# Add the MCP server; equivalent to ...--scope local...
claude mcp add cov-loupe cov-loupe -- -m mcp

# For user-wide configuration
claude mcp add --scope user cov-loupe cov-loupe -- -m mcp

# For project-specific configuration.
claude mcp add --scope project cov-loupe cov-loupe -- -m mcp

# List configured MCP servers
claude mcp list

# Get server details
claude mcp get cov-loupe

# Remove if needed (use --scope to match where it was added)
claude mcp remove cov-loupe                # Removes from local scope (default)
claude mcp remove --scope user cov-loupe   # Removes from user scope
claude mcp remove --scope project cov-loupe # Removes from project scope
```

### Codex

`mcp add` expects first the display name, then the executable (filename or path). The executable's filename is sufficient if it is in the PATH, but you may also specify the fully qualified path if necessary (e.g. `/a/b/cov-loupe`).

Using the Codex CLI:

```sh
# Add the MCP server
codex mcp add cov-loupe cov-loupe -m mcp

# List configured servers
codex mcp list

# Show server details
codex mcp get cov-loupe

# Remove if needed (check codex documentation for scope options if applicable)
codex mcp remove cov-loupe
```

**Important:** Codex does not pass environment variables like `GEM_HOME`/`GEM_PATH` to MCP servers
by default. After adding the server, you **must** manually edit `~/.codex/config.toml` to add the 'env_vars' setting:

```toml
[mcp_servers.cov-loupe]
command = "cov-loupe"
args = ["-m", "mcp"]
env_vars = ["GEM_HOME", "GEM_PATH"]  # Add this line manually
```

**Warning:** If you run `codex mcp remove cov-loupe`, the `env_vars` line will be deleted along with the rest of the section.
You'll need to manually add it back after running `codex mcp add` again.
To avoid this, consider editing `~/.codex/config.toml` directly instead of using `remove`/`add` commands.

If Codex starts `cov-loupe` in a fresh repo and you see `Resolving dependencies...` before the MCP handshake, point Codex at a small wrapper script instead of `cov-loupe` directly:

```sh
#!/usr/bin/env bash
export NOEXEC_DISABLE=1
exec cov-loupe -m mcp "$@"
```

That disables `rubygems-bundler`'s `noexec` hook before the RubyGems launcher runs, which keeps `stdout` clean for MCP startup.

### Gemini

`mcp add` expects first the display name, then the executable (filename or path). The executable's filename is sufficient if it is in the PATH, but you may also specify the fully qualified path if necessary (e.g. `/a/b/cov-loupe`).

Using the Gemini CLI:

```sh
# Add the MCP server
gemini mcp add cov-loupe cov-loupe -- -m mcp

# List configured servers
gemini mcp list

# Remove if needed (check gemini documentation for scope options if applicable)
gemini mcp remove cov-loupe
```


**Environment variables you can set:**

- `COV_LOUPE_OPTS` - Default CLI options (though less useful for MCP mode)

### Kilo

For global configuration, create or edit `~/.config/kilo/opencode.json`. For project-local configuration, use `opencode.json` in the project root:

```json
{
  "$schema": "https://kilo.ai/config.json",
  "mcp": {
    "cov-loupe": {
      "type": "local",
      "command": ["cov-loupe", "-m", "mcp"],
      "enabled": true
    }
  }
}
```

**Note:** Ensure `cov-loupe` is in your PATH. If installed via Bundler, you may need to use the full path (e.g., `bundle exec cov-loupe`) or create a wrapper script.

## Stdout Must Stay Clean During MCP Startup

MCP over stdio is strict: the server must not print anything to `stdout` before the MCP handshake begins. The first bytes on `stdout` must be protocol traffic. Any banner, warning, dependency-resolution message, or debug output written before that point can cause the client to reject startup or report a handshake failure.

This matters for `cov-loupe` because there are two common launch paths:

- The gem's real executable, [`exe/cov-loupe`](../../exe/cov-loupe), which simply loads `cov_loupe` and calls `CovLoupe.run(ARGV)`.
- The RubyGems-installed `cov-loupe` stub and wrapper stack, which are generated outside this repository and may call `Gem.use_gemdeps` and `rubygems-bundler` hooks before activating the gem.

On systems where the installed stub includes:

```ruby
require 'rubygems'
Gem.use_gemdeps
```

the launcher may consult the current working directory's Bundler context before `cov-loupe` itself starts. On setups that also use `ruby_executable_hooks` plus the `rubygems-bundler` plugin, that wrapper stack can walk up from the current directory, inspect `Gemfile`, and call Bundler before `cov-loupe` runs. When that bundle is unresolved or incomplete, Bundler may resolve dependencies and emit progress text such as `Resolving dependencies...` before `cov-loupe` has a chance to start the MCP transport.

That output does not come from `cov-loupe`'s own [`exe/cov-loupe`](../../exe/cov-loupe). It happens earlier, in the generated launcher and the dependency tooling it invokes.

The upstream tracking issue for this RVM launcher-stack behavior is [rvm/rvm#5649](https://github.com/rvm/rvm/issues/5649).

### Why One Project Can Fail While Another Works

Different working directories can produce different startup behavior because the RubyGems stub consults the current directory's gem dependency state:

- A directory with a settled bundle, valid `Gemfile.lock`, and successful `bundle check` often starts cleanly because Bundler does not need to resolve anything.
- A directory with a `Gemfile` but no lockfile, missing gems, or otherwise incomplete bundle state may trigger dependency resolution before `cov-loupe` starts.

That is why `cov-loupe -m mcp` can work in one repo and fail in another even though the same gem installation and MCP client configuration are being used.

### Why `bundle install` Can Make the Symptom Disappear

Running `bundle install` in the current project usually creates or settles `Gemfile.lock` and installs the gems Bundler expects. After that, the RubyGems stub may no longer need to resolve dependencies at startup, so the extra stdout message disappears and MCP can start normally.

This can make the issue look intermittent, but the underlying cause is consistent: the generated RubyGems launcher is sensitive to the current directory's Bundler state.

### Recommended Launch Patterns

For MCP usage, start with the normal launch path and only bypass the RubyGems stub if you still need to.

- Most reliable workaround for wrapper-heavy Ruby environments: launch through a tiny shell wrapper that exports `NOEXEC_DISABLE=1` before calling `cov-loupe -m mcp`.
- Preferred fix: in the current project, run `bundle install` so the bundle is settled, then retry normal `cov-loupe -m mcp` startup.
- Good follow-up check: confirm `Gemfile.lock` exists and `bundle check` succeeds before retrying the MCP client.
- Fallback: if you cannot settle the bundle or still need a launch path that does not depend on the working directory's bundle state, invoke the real executable directly instead of the RubyGems wrapper.
- Good for local development from a checkout: point the MCP client at the checkout's [`exe/cov-loupe`](../../exe/cov-loupe) directly.

Example wrapper:

```sh
#!/usr/bin/env bash
export NOEXEC_DISABLE=1
exec cov-loupe -m mcp "$@"
```

This works because `rubygems-bundler` checks `NOEXEC_DISABLE` before it tries to load the current directory's bundle, so the wrapper keeps `stdout` clean for MCP startup.

To find the real executable path for an installed gem:

```sh
ruby -e 'spec = Gem::Specification.find_by_name("cov-loupe"); puts File.join(spec.full_gem_path, "exe", "cov-loupe")'
```

Then configure the MCP client to run that path with `-m mcp`, for example:

```toml
[mcp_servers.cov-loupe]
command = "/absolute/path/to/gems/cov-loupe-5.0.0/exe/cov-loupe"
args = ["-m", "mcp"]
```

or:

```json
{
  "mcp": {
    "cov-loupe": {
      "type": "local",
      "command": ["/absolute/path/to/gems/cov-loupe-5.0.0/exe/cov-loupe", "-m", "mcp"],
      "enabled": true
    }
  }
}
```

**Tradeoff:** the real executable path usually includes the installed gem version, so you may need to update your MCP config after upgrading `cov-loupe`.

### Guidance for `cov-loupe -m mcp`

Running `cov-loupe -m mcp` through the RubyGems-installed stub is the normal supported startup path, and it is usually fine when:

- the current directory has no interfering `Gemfile`, or
- the current directory's bundle is already settled and quiet at startup.

If startup fails in a repo with a `Gemfile`, first try either a wrapper that exports `NOEXEC_DISABLE=1` or settling that repo's bundle with `bundle install`, then retry normal `cov-loupe -m mcp` startup. Only if that is not practical, or if you need a launch path insulated from the working directory's Bundler state, should you bypass the stub and point your MCP client at the real executable. If you need to follow upstream progress, see [rvm/rvm#5649](https://github.com/rvm/rvm/issues/5649).

## Available MCP Tools (Functions)

### Tool Catalog

cov-loupe exposes 9 MCP tools:

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `file_coverage_summary` | File coverage summary | `path` |
| `file_coverage_detailed` | Per-line coverage | `path` |
| `file_coverage_raw` | Raw SimpleCov array | `path` |
| `file_uncovered_lines` | List uncovered lines | `path` |
| `project_coverage` | Project-wide coverage (JSON, table, YAML, etc.) | `sort_order`, `tracked_globs`, `format` |
| `project_coverage_totals` | Aggregated line totals | `tracked_globs` |
| `project_validate` | Validate coverage policies | `code` or `file` |
| `help` | Tool discovery | (none) |
| `version` | Version information | (none) |

### JSON Response Format

For tools that return structured data, `cov-loupe` serializes the data as a JSON string and returns it inside a `text` part of the MCP response.

**Example:**
```json
{
  "type": "text",
  "text": "{\"file\":\"lib/foo.rb\",\"summary\":{\"covered\":10,\"total\":20,\"percentage\":50.0},\"stale\":\"ok\"}"
}
```

**Reasoning:**
While returning JSON in a `resource` part with `mimeType: "application/json"` is more semantically correct, major MCP clients (including Google's Gemini and Anthropic's Claude) were found to not support this format, causing validation errors. They expect a `resource` part to contain a `uri`.

To ensure maximum compatibility, the decision was made to use a simple `text` part. This is a pragmatic compromise that has proven to be reliable across different clients.

**Further Reading:**
This decision was informed by discussions with multiple AI models. For more details, see these conversations:
- [Perplexity AI Discussion](https://www.perplexity.ai/search/title-resolving-a-model-contex-IfpFWU1FR5WQXQ8HcQctyg#0)
- [ChatGPT Discussion](https://chatgpt.com/share/68e4d7e1-cad4-800f-80c2-58b33bfc31cb)

### CLI Options in MCP Mode

When the MCP server starts, you can pass CLI options via the startup command. These options become the default config for MCP tools. **Per-request JSON parameters still win over CLI defaults.**

| CLI Option | Affects MCP Server? | JSON Parameter | Notes |
|------------|-------------------|----------------|-------|
| `-R`, `--root` | ✅ Default | `root` | Request param overrides; CLI sets default |
| `-r`, `--resultset` | ✅ Default | `resultset` | Request param overrides; CLI sets default |
| `-S`, `--raise-on-stale` | ✅ Default | `raise_on_stale` | Request param overrides; CLI sets default (`false` or `true`) |
| `-g`, `--tracked-globs` | ✅ Default | `tracked_globs` | Request param overrides; CLI sets default (array) |
| `--error-mode` | ✅ Yes | `error_mode` | Sets server-wide error handling; can override per tool |
| `-l`, `--log-file` | ✅ Yes | N/A | Sets server log location (cannot override per tool) |
| `-f`, `--format` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-o`, `--sort-order` | ❌ No | `sort_order` | CLI flag ignored in MCP; pass per tool call (`\"ascending\"` or `\"descending\"`) |
| `-s`, `--source` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-c`, `--context-lines` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-C`, `--color BOOLEAN` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-m`, `--mode` | ✅ Required | N/A | **Required for MCP mode:** `-m mcp` or `--mode mcp`. Default: `cli`. |

**Key Takeaways:**
- **Server-level options** (`--error-mode`, `--log-file`): Set once when server starts, apply to all tool calls
- **Tool-level options** (`root`, `resultset`, `raise_on_stale`, `tracked_globs`): CLI args provide defaults; per-tool JSON params override when provided
- **CLI-only options** (`--format`, `--source`, etc.): Not applicable to MCP mode

**Precedence for MCP tool config:** `JSON request param` > `CLI args used to start MCP` (including `COV_LOUPE_OPTS`) > built-in defaults (`root: '.'`, `raise_on_stale: false`, `resultset: nil`, `tracked_globs: []` - no filtering, no tracking).

CLI-only presentation flags (`-f/--format`, `-s/--source`, `-c/--context-lines`, `-C/--color`, and CLI `-o/--sort-order` defaults) never flow into MCP. Pass `sort_order` explicitly in each tool request when you need non-default ordering.

**Data caching:** Coverage data is cached in a global singleton (`ModelDataCache`) and shared across all `CoverageModel` instances. When the resultset file changes (based on file signature and MD5 digest), the cache automatically reloads fresh data. Model instances themselves are lightweight and created fresh for each tool request.

### Common Parameters

All file-specific tools accept these parameters in the JSON request:

- `path` (required for file tools) - File path (relative or absolute)
- `root` (optional) - Project root directory (default: `.`)
- `resultset` (optional) - Path to the `.resultset.json` file. See [Configuring the Resultset](../index.md#configuring-the-resultset) for details.
- `raise_on_stale` (optional) - Raise error on staleness: `false` (default) or `true`
- `error_mode` (optional) - Error handling: `"off"`, `"log"` (default), `"debug"` (overrides server-level setting)

### Tool Details

#### Per-File Tools

These tools analyze individual files. All require `path` parameter.

**`file_coverage_summary`** - Covered/total/percentage summary
```json
{"file": "...", "summary": {"covered": 12, "total": 14, "percentage": 85.71}, "stale": "ok"}
```

**`file_uncovered_lines`** - List uncovered line numbers
```json
{"file": "...", "uncovered": [5, 9, 12], "summary": {...}, "stale": "ok"}
```

**`file_coverage_detailed`** - Per-line hit counts
```json
{"file": "...", "lines": [{"line": 1, "hits": 1, "covered": true}, ...], "summary": {...}, "stale": "ok"}
```

**`file_coverage_raw`** - Raw SimpleCov lines array
```json
{"file": "...", "lines": [1, 0, null, 5, 2, null, 1], "stale": "ok"}
```

**Staleness values:** `"ok"` (fresh), `"missing"` (missing), `"newer"` (timestamp), `"length_mismatch"` (length), `"error"` (staleness check error)

#### Project-Wide Tools

**`project_coverage`** - Coverage for all files in various formats
- Parameters: `sort_order` (`ascending`|`descending`), `tracked_globs` (array), `format` (`json`|`pretty_json`|`yaml`|`amazing_print`|`table`)
- Default format: `json`
- Returns: JSON object (format dependent):
  - JSON/pretty_json/yaml/amazing_print: `{"files": [...], "counts": {"total": N, "ok": N, "stale": N}, "skipped_files": [...], "missing_tracked_files": [...], "newer_files": [...], "deleted_files": [...], "length_mismatch_files": [...], "unreadable_files": [...], "timestamp_status": "ok|missing", "warnings": [...]}`
  - Table: Plain text table with box-drawing characters

**`project_coverage_totals`** - Aggregated line totals
- Parameters: `tracked_globs` (array), `raise_on_stale`
- Returns: `{"lines":{"total":N,"covered":N,"uncovered":N,"percentage":Float},"tracking":{"enabled":Boolean,"globs":[String]},"files":{"total":N,"with_coverage":{"total":N,"ok":N,"stale":{"total":N,"by_type":{"missing_from_disk":N,"newer":N,"length_mismatch":N,"unreadable":N}}},"without_coverage":{"total":N,"by_type":{"missing_from_coverage":N,"unreadable":N,"skipped":N}}}}`
- `without_coverage` is only present when tracking is enabled (tracked globs provided).

#### Policy Validation Tools

**`project_validate`** - Validate coverage against custom policies
- Parameters: Either `code` (Ruby string) OR `file` (path to Ruby file), plus optional `root`, `resultset`, `raise_on_stale`, `error_mode`
- Returns: `{"result": Boolean}` where `true` means policy passed, `false` means failed
- Security Warning: Predicates execute as arbitrary Ruby code with full system privileges. Only use predicate files from trusted sources.
- Examples:
    - Check if all files have at least 80% coverage: `{"code": "->(m) { m.list[\"files\"].all? { |f| f['percentage'] >= 80 } }"}`
    - Run coverage policy from file: `{"file": "coverage_policy.rb"}`

#### Utility Tools

**`help`** - Tool discovery and canonical resource values
**`version`** - Version information

`help` returns:
- `tools` - guidance for each MCP tool (`use_when`, `avoid_when`, `inputs`)
- `resources` - canonical shared resource values:
    - `repo` (public GitHub URL)
    - `docs` (public docs URL)
    - `docs-local` (absolute path to local README)

Example `help` payload excerpt:
```json
{
  "resources": {
    "repo": "https://github.com/keithrbennett/cov-loupe",
    "docs": "https://keithrbennett.github.io/cov-loupe/",
    "docs-local": "/abs/path/to/README.md"
  }
}
```

## Example Prompts for AI Assistants

(Hopefully, your AI agent will not need you to explicilty specify "Using cov-loupe",
but this is included here because we have seen cases where it does not know to use cov-loupe.)
### Coverage Analysis

```
Using cov-loupe, show me a table of all files and their coverage percentages.
```

```
Using cov-loupe, find files with less than 80% coverage and tell me which ones to prioritize.
```

```
Using cov-loupe, analyze the coverage for lib/cov_loupe/tools/ and suggest improvements.
```

### Finding Coverage Gaps

```
Using cov-loupe, show me the uncovered lines in lib/cov_loupe/base_tool.rb and explain what they do.
```

```
Using cov-loupe, find the most important uncovered code in lib/cov_loupe/tools/file_coverage_detailed_tool.rb.
```

### Test Generation

```
Using cov-loupe, find uncovered lines in lib/cov_loupe/staleness_checker.rb and write *meaningful* RSpec tests for them.
```

```
Using cov-loupe, analyze coverage gaps in lib/cov_loupe/tools/ and generate test cases.
```

### Coverage Reporting

```
Using cov-loupe, create a markdown report of:
- Files with worst coverage
- Most critical coverage gaps
- Recommended action items
```

## Testing Your Setup

### Manual Testing via Command Line

Test the MCP server responds to JSON-RPC:

```sh
# Prefer the real executable or a known-clean working directory for MCP tests.
# Test version tool (simplest, no parameters needed)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp

# Test help tool (no parameters needed)
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"help","arguments":{}}}' | cov-loupe -m mcp

# Test summary tool (use root param if needed)
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"lib/cov_loupe/model.rb","root":"."}}}' | cov-loupe -m mcp

# Test with a project-specific root
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"app/models/order.rb","root":"docs/fixtures/demo_project"}}}' | cov-loupe -m mcp
```

**Important Notes:**
- JSON-RPC messages must be on a single line. Multi-line JSON will cause parse errors.
- CLI flags like `-R` set server defaults, but per-request JSON parameters still win.
- The `root` parameter is optional and defaults to `.` (current directory).
- If you see text such as `Resolving dependencies...` before the JSON-RPC response, your launcher polluted `stdout` before MCP startup. See [Stdout Must Stay Clean During MCP Startup](#stdout-must-stay-clean-during-mcp-startup).

### Testing in AI Assistant

Once configured, try these prompts in your AI assistant:

1. **Basic connectivity:**
   ```
   Using cov-loupe, show me the version.
   ```

2. **List tools:**
   ```
   Using cov-loupe, what tools are available?
   ```

3. **Simple query:**
   ```
   Using cov-loupe, show me all files with coverage.
   ```

If these work, your setup is correct!

### Checking Logs

The MCP server logs to `cov_loupe.log` in the current directory by default.

```sh
# Watch logs in real-time
tail -f cov_loupe.log

# View recent errors
grep ERROR cov_loupe.log | tail -20
```

To override the default log file location, specify the `--log-file` (or `-l`) argument wherever and however you configure your MCP server. For example, to log to a different file path, include `-l /path/to/logfile.log` in your server configuration. To log to standard error, use `-l stderr`. To disable logging entirely, use `-l :off` (cross-platform alternative to `/dev/null`).

**Warning:** Log files may grow unbounded in long-running or CI usage. Consider using a log rotation tool or periodically cleaning up the log file if this is a concern.

**Note:** Logging to `stdout` is not permitted in MCP mode.

## Troubleshooting

### CLI Fallback

**Important:** If the MCP server doesn't work, you can use the CLI directly with the `-fJ` (output in JSON format) flag.

See the **[CLI Fallback for LLMs Guide](CLI_FALLBACK_FOR_LLMS.md)** for:
- Complete command reference and MCP tool mappings
- Sample prompt to give your LLM
- JSON output examples
- Tips for using CLI as an MCP alternative

### Common Issues

**Server Won't Start**
```sh
which cov-loupe     # Verify executable exists
ruby -v             # Check Ruby >= 3.2
cov-loupe --version   # Test basic functionality
```

**Server fails only in some project directories**

If `cov-loupe -m mcp` works in one repo but fails in another, especially with text like `Resolving dependencies...` appearing before the MCP handshake, see [Stdout Must Stay Clean During MCP Startup](#stdout-must-stay-clean-during-mcp-startup). This usually means the RubyGems launcher consulted the current directory's `Gemfile` and Bundler printed to `stdout` before the MCP server started. The first fix to try is `bundle install` in that repo, followed by another normal startup attempt.

**Tools Not Appearing**
1. Restart AI assistant after config changes
2. Check logs: `tail -f cov_loupe.log`
3. Try explicit tool names in prompts
4. Verify MCP server status in assistant

**JSON-RPC Parse Errors**
- Ensure JSON is on a single line (no newlines)
- Test manually: `echo '{"jsonrpc":"2.0",...}' | cov-loupe -m mcp`

## Advanced Configuration

### Enable Debug Logging

For troubleshooting, add error mode when configuring the server:

```sh
# Claude Code
claude mcp add cov-loupe cov-loupe -- -m mcp --error-mode debug

# Codex
codex mcp add cov-loupe cov-loupe -m mcp --error-mode debug

# Gemini
gemini mcp add cov-loupe cov-loupe -- -m mcp --error-mode debug
```

## Next Steps

- **[CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md)** - Using CLI when MCP isn't available
- **[CLI Usage](CLI_USAGE.md)** - Complete CLI reference
- **[Examples](EXAMPLES.md)** - Example prompts and workflows
- **[Troubleshooting](TROUBLESHOOTING.md)** - Detailed troubleshooting guide
