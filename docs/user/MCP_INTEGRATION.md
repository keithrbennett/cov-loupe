# MCP Integration Guide

[Back to main README](../index.md)

> **⚠️ BREAKING CHANGE (v4.0.0+):** The `-m/--mode mcp` flag is now **required** to run cov-loupe as an MCP server. 
> Automatic mode detection based on TTY/stdin has been removed. If you're upgrading from an earlier version, you **must** update your MCP server configuration to include `-m mcp` or `--mode mcp` or the server will run in CLI mode and hang. See [Migration Guide](migrations/MIGRATING_TO_V4.md) for details.

## Table of Contents

- [Setup by Client](#setup-by-client)
    - [Claude Code](#claude-code)
    - [Codex](#codex)
    - [Antigravity](#antigravity)
    - [GitHub Copilot CLI](#github-copilot-cli)
    - [Cursor](#cursor)
    - [VS Code](#vs-code)
    - [Kimi Code](#kimi-code)
    - [OpenCode](#opencode)
    - [Pi](#pi)
    - [Kilo](#kilo)
- [Stdout Must Stay Clean During MCP Startup](#stdout-must-stay-clean-during-mcp-startup)
- [Available MCP Tools](#available-mcp-tools-functions)
    - [JSON Response Format](#json-response-format)
    - [Error Responses](#error-responses)
- [Testing Your Setup](#testing-your-setup)
- [Troubleshooting](#troubleshooting)

## Setup by Client

> **Tip:** If you use RVM (or otherwise see `Resolving dependencies...` printed before the MCP handshake), skip straight to [the launch wrapper](#step-by-step-the-launch-wrapper). It takes one minute and prevents a common startup failure in every client below.

> **Note:** This section is best-effort research meant to help you get started. Not every client has been fully verified, and these tools change quickly, so commands and file locations may differ by the time you read this. If something doesn't work, check your client's own documentation (e.g., `claude mcp --help`, `codex mcp --help`, `agy mcp --help`, `opencode mcp --help`).

> **Note:** If you try a one-shot, non-interactive test (for example, running your client with `-p` or `exec`) and it fails, it may be because there is nobody to answer the client's permission prompt for the MCP tool call, so the call is blocked or denied even though the server itself works. Pre-authorize the tool in your client's settings, or test interactively. See also [Confirm the server actually starts](#confirm-the-server-actually-starts).

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

# Remove if needed. Without --scope, it is removed from whichever scope it exists in;
# use --scope to be explicit (or if the same name exists in more than one scope)
claude mcp remove cov-loupe
claude mcp remove --scope user cov-loupe
claude mcp remove --scope project cov-loupe
```

### Codex

`mcp add` expects first the display name, then `--`, then the executable (filename or path) and its arguments. The executable's filename is sufficient if it is in the PATH, but you may also specify the fully qualified path if necessary (e.g. `/a/b/cov-loupe`).

Using the Codex CLI:

```sh
# Add the MCP server (global; stored in ~/.codex/config.toml)
codex mcp add cov-loupe -- cov-loupe -m mcp

# List configured servers
codex mcp list

# Show server details
codex mcp get cov-loupe

# Remove if needed
codex mcp remove cov-loupe
```

**Important:** Codex starts MCP servers with a minimal environment and does not pass `GEM_HOME`/`GEM_PATH` by default. If you installed `cov-loupe` with `gem install` under RVM (where Ruby finds gems through those two variables), Codex cannot find the gem and the launcher fails with `can't find gem cov-loupe`. Codex shows no error: `codex mcp list` reports the server as `enabled`, but it never starts, and the model may answer without it (or invent an answer). After adding the server, you **must** manually edit `~/.codex/config.toml` to add the `env_vars` setting:

```toml
[mcp_servers.cov-loupe]
command = "cov-loupe"
args = ["-m", "mcp"]
env_vars = ["GEM_HOME", "GEM_PATH"]  # Add this line manually
```

**Warning:** If you run `codex mcp remove cov-loupe`, the `env_vars` line will be deleted along with the rest of the section.
You'll need to manually add it back after running `codex mcp add` again.
To avoid this, consider editing `~/.codex/config.toml` directly instead of using `remove`/`add` commands.

**Watch the position of `--`.** It goes right after the server name and *before* the command: `codex mcp add cov-loupe -- cov-loupe -m mcp` (name, `--`, command, arguments). If you put the command before the `--`, as in `codex mcp add cov-loupe cov-loupe -- -m mcp`, Codex stores the `--` as a literal argument: `args = ["--", "-m", "mcp"]`, and `cov-loupe` fails with `Unknown subcommand: '-m'`. After adding, confirm that the `Args` column of `codex mcp list` shows `-m mcp` with no leading `--`.

If Codex starts `cov-loupe` in a repo and you see `Resolving dependencies...` before the MCP handshake, use the [launch wrapper](#step-by-step-the-launch-wrapper) below instead of `cov-loupe` directly.

### Antigravity

Antigravity's CLI is `agy`. `mcp add` expects first the display name, then the executable and its arguments; flags (such as `--env`) must come before the name, and `--` is needed so `-m` is not parsed as a flag.

```sh
# Add the MCP server (user-wide; stored in ~/.gemini/config/mcp_config.json)
agy mcp add cov-loupe cov-loupe -- -m mcp

# List configured servers
agy mcp list

# Temporarily turn the server off or on without removing it
agy mcp disable cov-loupe
agy mcp enable cov-loupe

# Remove if needed
agy mcp remove cov-loupe
```

`agy mcp` has no `--scope` option; configuration is user-wide.

**Gemini CLI:** Google has [replaced Gemini CLI with Antigravity CLI](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/); Gemini CLI stopped serving free, AI Pro, and Ultra personal accounts on June 18, 2026. Access through Gemini Code Assist Standard or Enterprise licenses is unchanged. If you are on one of those, `gemini mcp add cov-loupe cov-loupe -- -m mcp` adds the server to the project (`.gemini/settings.json`); add `--scope user` for user-wide configuration (`~/.gemini/settings.json`). `gemini mcp remove` takes the same `--scope` option, and its default scope is also project.

### GitHub Copilot CLI

`mcp add` expects the display name, then `--`, then the command and its arguments. It always writes to your user configuration, `~/.copilot/mcp-config.json`.

```sh
# Add the MCP server (user-wide)
copilot mcp add cov-loupe -- cov-loupe -m mcp

# List configured servers, or show one
copilot mcp list
copilot mcp get cov-loupe

# Remove if needed (user configuration only)
copilot mcp remove cov-loupe
```

Copilot also reads project servers from `.mcp.json` or `.github/mcp.json` in the workspace. Those can't be managed with `copilot mcp add/remove`; edit the file instead.

`copilot mcp list` only reads configuration. To see whether the server actually starts, run any prompt with debug logging and look for the connection lines:

```sh
copilot -p "hi" --log-level debug --log-dir /tmp/copilot-logs
grep "cov-loupe" /tmp/copilot-logs/*
```

You should see `MCP client for cov-loupe connected`.

### Cursor

Cursor reads `mcp.json` files: `~/.cursor/mcp.json` (all projects) or `.cursor/mcp.json` (one project), using the `mcpServers` format. Cursor launches servers **without** your shell's `GEM_HOME`/`GEM_PATH`, so if you installed `cov-loupe` with `gem install` under RVM (where Ruby finds gems through those two variables), you need to pass them explicitly (Cursor expands `${env:NAME}` from its own environment):

```json
{
  "mcpServers": {
    "cov-loupe": {
      "command": "cov-loupe",
      "args": ["-m", "mcp"],
      "env": {
        "GEM_HOME": "${env:GEM_HOME}",
        "GEM_PATH": "${env:GEM_PATH}"
      }
    }
  }
}
```

Without the `env` block, `cursor-agent mcp list-tools cov-loupe` fails with `Connection failed` and `can't find gem cov-loupe` from the launcher.

Cursor also asks you to approve each server before it will start it. Approve it from the command line, and repeat this if you later edit the server's entry, because the approval is reset by a change:

```sh
cursor-agent mcp enable cov-loupe
cursor-agent mcp list                    # should show: cov-loupe: ready
cursor-agent mcp list-tools cov-loupe    # starts the server and lists its 9 tools; no model needed
```

To remove the server, delete its entry from `mcp.json` (or run `cursor-agent mcp disable cov-loupe` to stop it loading while keeping the entry).

### VS Code

VS Code (with Copilot Chat's agent mode) stores MCP servers in an `mcp.json` file. The top-level key is `servers` (not `mcpServers`). You can add a server to your user profile from the command line:

```sh
code --add-mcp '{"name":"cov-loupe","command":"cov-loupe","args":["-m","mcp"]}'
```

For one project only, create `.vscode/mcp.json`:

```json
{
  "servers": {
    "cov-loupe": {
      "type": "stdio",
      "command": "cov-loupe",
      "args": ["-m", "mcp"]
    }
  }
}
```

There is no command-line remove; delete the `cov-loupe` entry from the file. The editor's `MCP: List Servers` command lets you start, stop, restart, and view the output of a server.

Editors started from a desktop launcher often don't inherit your shell environment, so if the server fails to start, use the [launch wrapper](#step-by-step-the-launch-wrapper) with its absolute path.

### Kimi Code

Kimi Code (`kimi`) has no `mcp add`/`mcp remove` subcommands. MCP servers are declared in `mcp.json` files, each with a top-level `mcpServers` object:

| Scope | File |
|-------|------|
| User-global | `~/.kimi-code/mcp.json` (or `$KIMI_CODE_HOME/mcp.json` if that variable is set) |
| Project root (shared with other tools) | `.mcp.json` at the repository root |
| Project-local (Kimi-specific) | `.kimi-code/mcp.json` in the current directory |

```json
{
  "mcpServers": {
    "cov-loupe": {
      "command": "cov-loupe",
      "args": ["-m", "mcp"]
    }
  }
}
```

To add the server, create the file or merge this entry into an existing `mcpServers` object. To remove it, delete the `cov-loupe` entry from the file where it was added. MCP servers load at session start, so start a new session (e.g. `/new`) or restart `kimi` afterward. You can also ask Kimi to make the change for you with the `/mcp-config` skill.

Project-root and project-local entries launch commands at session start, so Kimi loads them only in folders you have marked as trusted. In an untrusted folder it skips them and prints `this folder is not trusted; skipped 1 project-level MCP server: cov-loupe`. To trust the folder, run `kimi` there interactively and choose "Trust this folder"; non-interactive runs (`kimi -p`) cannot ask. The user-global `mcp.json` needs no trust, so it is the simplest choice if you want cov-loupe available everywhere.

### OpenCode

OpenCode can add servers interactively with `opencode mcp add` (it prompts for name, type, and command), and `opencode mcp list` shows what is configured and its status. There is no `opencode mcp remove`; to add non-interactively or to remove a server, edit the config file directly. For global configuration, use `~/.config/opencode/opencode.json`; for project-local configuration, use `opencode.json` in the project root:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "cov-loupe": {
      "type": "local",
      "command": ["cov-loupe", "-m", "mcp"],
      "enabled": true
    }
  }
}
```

To remove the server, delete the `cov-loupe` entry from `mcp` (or set `"enabled": false` to keep the entry but not start it), then restart OpenCode.

### Pi

Pi does not include built-in MCP support. To use cov-loupe with Pi, install the community [`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter) extension and restart Pi:

```sh
pi install npm:pi-mcp-adapter
```

The adapter reads standard `mcp.json` files: `.mcp.json` in the project root (project-specific), or `~/.config/mcp/mcp.json` (all projects). Add the server to either one:

```json
{
  "mcpServers": {
    "cov-loupe": {
      "command": "cov-loupe",
      "args": ["-m", "mcp"]
    }
  }
}
```

By default `pi install` is user-wide; add `-l` (`pi install npm:pi-mcp-adapter -l`) to install it for the current project only. In non-interactive runs (`pi -p`), Pi ignores project-local extensions (including a `-l` install) unless you pass `--approve` to trust project-local files for that run.

The adapter exposes MCP tools through a single `mcp` proxy tool and connects to servers lazily, so ask Pi to search for or call the cov-loupe tools (for example, "Using the cov-loupe MCP server, show me the version"). Inside Pi, `/mcp` shows the adapter's status and `/mcp setup` walks through configuration.

To remove the server, delete the `cov-loupe` entry from the `mcp.json` file where you added it and run `/reload` (or restart Pi). To remove the adapter itself, run `pi remove npm:pi-mcp-adapter`. See the adapter's README for its other config locations and precedence rules.

### Kilo

For global configuration, create or edit `~/.config/kilo/kilo.json`. For project-local configuration, use `kilo.json` in the project root or `.kilo/kilo.json` (`kilo.jsonc` is also supported):

```json
{
  "mcp": {
    "cov-loupe": {
      "type": "local",
      "command": ["cov-loupe", "-m", "mcp"],
      "enabled": true
    }
  }
}
```

`kilo mcp list` shows the configured servers. There is no `kilo mcp remove`; to remove the server, delete its entry from `mcp` (or set `"enabled": false` to keep it but not start it), then restart Kilo.

**Note:** Ensure `cov-loupe` is in your `PATH`, or use the [launch wrapper](#step-by-step-the-launch-wrapper).

## Stdout Must Stay Clean During MCP Startup

MCP over stdio is strict: the server must not print anything to `stdout` before the MCP handshake begins. Any banner, warning, dependency-resolution message, or debug output written before that point can cause the client to reject startup or report a handshake failure.

When `cov-loupe -m mcp` is launched through a RubyGems-installed stub, wrapper layers can inspect the current directory's `Gemfile` before `cov-loupe` itself starts. In projects with no lockfile, missing gems, or an otherwise unsettled bundle, that can print text such as `Resolving dependencies...` and corrupt MCP startup.

For root-cause details, diagnostic commands, and the upstream RVM tracking issue, see [RubyGems Wrapper Prints to Stdout Before MCP Startup](TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup).

### Recommended Launch Patterns

For MCP usage, start with the normal launch path and only bypass the RubyGems stub if startup is still noisy.

- Most reliable workaround for wrapper-heavy Ruby environments: launch through a tiny shell wrapper that exports `NOEXEC_DISABLE=1` before calling `cov-loupe -m mcp`. See [Step by Step: The Launch Wrapper](#step-by-step-the-launch-wrapper).
- Preferred fix: in the current project, run `bundle install` so the bundle is settled, then retry normal `cov-loupe -m mcp` startup.
- Good follow-up check: confirm `Gemfile.lock` exists and `bundle check` succeeds before retrying the MCP client.
- Fallback: if you cannot settle the bundle or still need a launch path that does not depend on the working directory's bundle state, invoke the real executable directly instead of the RubyGems wrapper.
- Good for local development from a checkout: point the MCP client at the checkout's [`exe/cov-loupe`](https://github.com/keithrbennett/cov-loupe/blob/main/exe/cov-loupe) directly.

### Step by Step: The Launch Wrapper

If you would rather not think about Bundler at all, do this once. It works in every project directory, whether or not the project's bundle is settled.

**1. Create the wrapper** in a directory that is on your `PATH` (`~/.local/bin` is a common choice; check with `echo $PATH`):

```sh
mkdir -p ~/.local/bin
cat > ~/.local/bin/cov-loupe-no-bundler <<'EOF'
#!/usr/bin/env bash
export NOEXEC_DISABLE=1
exec cov-loupe -m mcp "$@"
EOF
chmod +x ~/.local/bin/cov-loupe-no-bundler
```

The script already includes `-m mcp`, so the client commands below don't need it.

**2. Check that it works.** You should see a JSON line and nothing else before it:

```sh
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe-no-bundler
```

**3. Register `cov-loupe-no-bundler` instead of `cov-loupe -m mcp`.** If `cov-loupe` is already registered with your client, remove it first (see that client's section above):

| Client | Command |
|--------|---------|
| Claude Code | `claude mcp add cov-loupe cov-loupe-no-bundler` |
| Codex | `codex mcp add cov-loupe -- cov-loupe-no-bundler` (then add `env_vars`, as described in the [Codex](#codex) section) |
| Antigravity | `agy mcp add cov-loupe cov-loupe-no-bundler` |
| GitHub Copilot CLI | `copilot mcp add cov-loupe -- cov-loupe-no-bundler` |
| Cursor | In `mcp.json`: `"command": "cov-loupe-no-bundler"` and no `args` (keep the `env` block described in the [Cursor](#cursor) section) |
| VS Code | `code --add-mcp '{"name":"cov-loupe","command":"cov-loupe-no-bundler"}'` |
| Kimi Code, Pi | In `mcp.json`: `"command": "cov-loupe-no-bundler"` and no `args` |
| OpenCode | In `opencode.json`: `"command": ["cov-loupe-no-bundler"]` |
| Kilo | In `kilo.json`: `"command": ["cov-loupe-no-bundler"]` |

If a client can't find the script (some launch servers with a minimal `PATH`), give it the absolute path instead, e.g. `/home/you/.local/bin/cov-loupe-no-bundler`.

`NOEXEC_DISABLE=1` turns off the `rubygems-bundler` hook that RVM installs, which is what prints `Resolving dependencies...` to `stdout`. It doesn't change what `cov-loupe` does.

See [Troubleshooting](TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup) for wrapper examples and direct-executable fallback configuration.

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

### Error Responses

Failed tool calls return a `tools/call` result with `isError: true` and an error message in the `content` array. The MCP SDK emits this result for argument-validation failures before cov-loupe runs; cov-loupe emits it for tool-execution failures such as bad paths, invalid predicates, and stale coverage. This is a **tool-result-level** signal, distinct from a **JSON-RPC error** response.

JSON-RPC `error` responses are reserved for protocol- and dispatch-level failures such as unknown methods, invalid JSON-RPC requests, and unknown tools. Input-schema validation failures are tool-result errors even though validation happens before the tool implementation runs.

**Successful tool call** — `isError: false`:

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "isError": false,
    "content": [
      {
        "type": "text",
        "text": "{\"tools\":[{\"tool\":\"file_coverage_summary\",...}]}"
      }
    ]
  }
}
```

**Tool-execution failure** — `isError: true`:

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": {
    "isError": true,
    "content": [
      {
        "type": "text",
        "text": "Error: file not found in coverage data: nonexistent.rb"
      }
    ]
  }
}
```

**Argument-validation failure** — `isError: true`:

```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "result": {
    "isError": true,
    "content": [
      {
        "type": "text",
        "text": "Missing required arguments: path"
      }
    ]
  }
}
```

Your MCP client should check `result.isError` before parsing the response content as a successful payload. `isError: false` means the tool succeeded and the content can be parsed normally; `isError: true` means the call failed. If the response itself contains an `error` object instead of a `result`, the failure is at the protocol or dispatch level.

### CLI Options in MCP Mode

When the MCP server starts, you can pass CLI options via the startup command. These options become the default config for MCP tools. **Per-request JSON parameters still win over CLI defaults.**

| CLI Option | Affects MCP Server? | JSON Parameter | Notes |
|------------|-------------------|----------------|-------|
| `-R`, `--root` | ✅ Default | `root` | Request param overrides; CLI sets default |
| `-c`, `--coverage-file` | ✅ Default | `coverage_file` | Request param overrides; CLI sets default |
| `-S`, `--raise-on-stale` | ✅ Default | `raise_on_stale` | Request param overrides; CLI sets default (`false` or `true`) |
| `-g`, `--tracked-globs` | ✅ Default | `tracked_globs` | Request param overrides; CLI sets default (array) |
| `--error-mode` | ✅ Yes | `error_mode` | Sets server-wide error handling; can override per tool |
| `-l`, `--log-file` | ✅ Yes | N/A | Sets server log location (cannot override per tool) |
| `-f`, `--format` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-o`, `--sort-order` | ❌ No | N/A | CLI flag ignored in MCP; pass `sort_order` per `project_coverage` tool call |
| `-s`, `--source` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-n`, `--context-lines` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-C`, `--color BOOLEAN` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-m`, `--mode` | ✅ Required | N/A | **Required for MCP mode:** `-m mcp` or `--mode mcp`. Default: `cli`. |

**Key Takeaways:**
- **Server-level options** (`--error-mode`, `--log-file`): Set once when server starts, apply to all tool calls
- **Tool-level options** (`root`, `coverage_file`, `raise_on_stale`, `tracked_globs`): CLI args provide defaults; per-tool JSON params override when provided
- **CLI-only options** (`--format`, `--source`, etc.): Not applicable to MCP mode

**Precedence for MCP tool config:** `JSON request param` > `CLI args used to start MCP` (including `COV_LOUPE_OPTS`) > built-in defaults (`root: '.'`, `raise_on_stale: false`, `coverage_file: nil`, `tracked_globs: []` - no filtering, no tracking).

CLI-only presentation flags (`-f/--format`, `-s/--source`, `-n/--context-lines`, `-C/--color`, and `-o/--sort-order`) never flow into MCP. Pass `sort_order` explicitly in each `project_coverage` tool request when you need non-default ordering.

**Data caching:** Coverage data is cached in a global singleton (`ModelDataCache`) and shared across all `CoverageModel` instances. When the coverage file changes (based on file signature and MD5 digest), the cache automatically reloads fresh data. Model instances themselves are lightweight and created fresh for each tool request.

### Common Parameters

All file-specific tools accept these parameters in the JSON request:

- `path` (required for file tools) - File path (relative or absolute)
- `root` (optional) - Project root directory (default: `.`)
- `coverage_file` (optional) - Path to the `coverage.json` file, or to a directory containing one. See [Configuring the Coverage File](../index.md#configuring-the-coverage-file) for details.
- `raise_on_stale` (optional) - Raise error on staleness: `false` (default) or `true`
- `error_mode` (optional) - Error handling: `"off"`, `"log"` (default), `"debug"` (overrides server-level setting)
- `output_chars` (optional) - Output character mode: `"default"`, `"fancy"`, or `"ascii"`

`project_coverage` additionally accepts `sort_order` (`"ascending"` or `"descending"`) and `format` (`"json"`, `"pretty_json"`, `"yaml"`, `"amazing_print"`, `"inspect"`, `"puts"`, `"pretty_print"`, `"table"`; short codes: `j`, `J`, `y`, `a`, `i`, `p`, `P`, `t`).

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
- Parameters: `sort_order` (`ascending`|`descending`), `tracked_globs` (array), `format` (`json`|`pretty_json`|`yaml`|`amazing_print`|`inspect`|`puts`|`pretty_print`|`table`)
- Default format: `json`
- Returns: JSON object (format dependent):
  - JSON/pretty_json/yaml/amazing_print/inspect/puts/pretty_print: `{"files": [...], "counts": {"total": N, "ok": N, "stale": N}, "skipped_files": [...], "missing_tracked_files": [...], "newer_files": [...], "deleted_files": [...], "length_mismatch_files": [...], "unreadable_files": [...], "timestamp_status": "ok|missing", "warnings": [...]}`
  - Table: Plain text table with box-drawing characters

**`project_coverage_totals`** - Aggregated line totals
- Parameters: `tracked_globs` (array), `raise_on_stale`
- Returns: `{"lines":{"total":N,"covered":N,"uncovered":N,"percentage":Float,"included_files":N,"excluded_files":N},"tracking":{"enabled":Boolean,"globs":[String]},"files":{"total":N,"with_coverage":{"total":N,"ok":N,"stale":{"total":N,"by_type":{"missing_from_disk":N,"newer":N,"length_mismatch":N,"unreadable":N}}},"without_coverage":{"total":N,"by_type":{"missing_from_coverage":N,"unreadable":N,"skipped":N}}},"timestamp_status":"ok|missing","warnings":[String]}`
- `without_coverage` is only present when tracking is enabled (tracked globs provided).
- `warnings` is present when `timestamp_status` is `"missing"`.

#### Policy Validation Tools

**`project_validate`** - Validate coverage against custom policies
- Parameters: Either `code` (Ruby string) OR `file` (path to Ruby file), plus optional `root`, `coverage_file`, `raise_on_stale`, `error_mode`
- Returns: `{"result": Boolean}` where `true` means policy passed, `false` means the predicate evaluated to false (the tool itself succeeded, so `isError: false`)
- Execution errors (syntax error in the predicate, missing predicate file, etc.) return `isError: true` with the friendly error message in `content`
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

(Hopefully, your AI agent will not need you to say "Using the cov-loupe MCP server", but it is included
here on purpose. Agents sometimes run the `cov-loupe` command-line app through the shell instead of
calling the MCP server, even when the server is installed.)

### Coverage Analysis

```
Using the cov-loupe MCP server, show me a table of all files and their coverage percentages.
```

```
Using the cov-loupe MCP server, find files with less than 80% coverage and tell me which ones to prioritize.
```

```
Using the cov-loupe MCP server, analyze the coverage for lib/cov_loupe/tools/ and suggest improvements.
```

### Finding Coverage Gaps

```
Using the cov-loupe MCP server, show me the uncovered lines in lib/cov_loupe/base_tool.rb and explain what they do.
```

```
Using the cov-loupe MCP server, find the most important uncovered code in lib/cov_loupe/tools/file_coverage_detailed_tool.rb.
```

### Test Generation

```
Using the cov-loupe MCP server, find uncovered lines in lib/cov_loupe/staleness/staleness_checker.rb and write *meaningful* RSpec tests for them.
```

```
Using the cov-loupe MCP server, analyze coverage gaps in lib/cov_loupe/tools/ and generate test cases.
```

### Coverage Reporting

```
Using the cov-loupe MCP server, create a markdown report of:
- Files with worst coverage
- Most critical coverage gaps
- Recommended action items
```

## Testing Your Setup

### Manual Testing via Command Line

Use these commands as smoke tests to confirm that the MCP server is installed, launches with your configuration, and responds to JSON-RPC over stdio. They are not an exhaustive error-contract test suite; the included error cases are optional sanity checks. See [Error Responses](#error-responses) for the full MCP failure model.

```sh
# Prefer the real executable or a known-clean working directory for MCP tests.
# Test version tool (simplest, no parameters needed)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp

# Test help tool (no parameters needed)
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"help","arguments":{}}}' | cov-loupe -m mcp

# Test summary tool (use root param if needed)
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"lib/cov_loupe/model/model.rb","root":"."}}}' | cov-loupe -m mcp

# Optional error sanity check: the response should contain a `result` with `isError: true`
echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"nonexistent.rb","root":"."}}}' | cov-loupe -m mcp

# Optional validation sanity check: this also returns a `result` with `isError: true`
echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{}}}' | cov-loupe -m mcp

# Test with a project-specific root
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"app/models/order.rb","root":"docs/fixtures/demo_project"}}}' | cov-loupe -m mcp
```

**Important Notes:**
- JSON-RPC messages must be on a single line. Multi-line JSON will cause parse errors.
- CLI flags like `-R` set server defaults, but per-request JSON parameters still win.
- The `root` parameter is optional and defaults to `.` (current directory).
- The `docs/fixtures/demo_project` example above uses a committed fixture whose coverage timestamp is deliberately set far in the future, so its responses are reproducible on a fresh clone.
- If you see text such as `Resolving dependencies...` before the JSON-RPC response, your launcher polluted `stdout` before MCP startup. See [Stdout Must Stay Clean During MCP Startup](#stdout-must-stay-clean-during-mcp-startup).

### Testing in AI Assistant

Once configured, try these prompts in your AI assistant:

1. **Basic connectivity:**
   ```
   Using the cov-loupe MCP server, show me the version.
   ```

2. **List tools:**
   ```
   Using the cov-loupe MCP server, what tools are available?
   ```

3. **Simple query:**
   ```
   Using the cov-loupe MCP server, show me all files with coverage.
   ```

If these work, your setup is correct!

#### Confirm the server actually starts

A server can be registered and still fail to start, and most `list` commands only read the configuration. `claude mcp list` (shows `✔ Connected`), `opencode mcp list` (shows `connected`), and `cursor-agent mcp list` (shows `ready`, once approved) do try to start it; `codex mcp list`, `agy mcp list`, and Kimi's config do not, so `enabled` there proves nothing. Use a real request to be sure. These non-interactive versions each call the `version` tool once (run them from a project directory, and compare the answer with `cov-loupe --version`):

| Client | Command |
|--------|---------|
| Claude Code | `claude -p "Call the cov-loupe MCP version tool and reply with only the version." --allowedTools mcp__cov-loupe__version` |
| Codex | `codex exec -c 'mcp_servers.cov-loupe.tools.version.approval_mode="approve"' "Call the cov-loupe MCP version tool (not the shell) and reply with only the version."` |
| GitHub Copilot CLI | `copilot -p "hi" --log-level debug --log-dir /tmp/copilot-logs`, then `grep cov-loupe /tmp/copilot-logs/*` and look for `MCP client for cov-loupe connected` |
| Cursor | `cursor-agent mcp list-tools cov-loupe` (after `cursor-agent mcp enable cov-loupe`); lists the tools without using a model |
| Kimi Code | `kimi -p "Call the cov-loupe MCP version tool and reply with only the version."` |
| OpenCode | `opencode run -m <provider/model> "Call the cov-loupe MCP version tool and reply with only the version."` |
| Pi | `pi -p "Use the mcp tool to call the cov-loupe version tool and reply with only the version."` (add `--approve` if the adapter is installed with `-l`) |

Notes:

- A model that can't reach the server may still answer, using the shell or a guess. If the version doesn't match `cov-loupe --version`, or the client didn't report a tool call to `cov-loupe`, treat it as a failure.

### Checking Logs

The MCP server logs tool-execution errors and other cov-loupe diagnostics to `stderr` by default. See the [logging initialization and target testing guide](LOGGING.md#log-file-initialization-and-target-testing) for details about startup probing, append-mode checks, cached failures, and explicit file targets. Argument-validation failures emitted by the MCP SDK before cov-loupe runs do not reach this logger.

```sh
# Watch an explicitly configured file in real-time
tail -f /path/to/your-configured-log-file.log

# View recent errors from an explicitly configured file
grep ERROR /path/to/your-configured-log-file.log | tail -20
```

To use a persistent log file, specify the `--log-file` (or `-l`) argument wherever and however you configure your MCP server. For example, include `-l /path/to/logfile.log` in your server configuration. To use standard error explicitly, use `-l stderr`. To disable logging entirely, use `-l :off` (cross-platform alternative to `/dev/null`).

**Warning:** Explicit log files may grow unbounded in long-running or CI usage. cov-loupe does not rotate them; use external rotation or periodically clean them up.

**Note:** Logging to `stdout` is not permitted in any mode, because it would corrupt command output or the MCP JSON-RPC protocol.

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
2. Check the MCP host's captured stderr, or the explicitly configured log file.
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
codex mcp add cov-loupe -- cov-loupe -m mcp --error-mode debug

# Antigravity
agy mcp add cov-loupe cov-loupe -- -m mcp --error-mode debug
```

For Kimi Code, OpenCode, and Pi, add `"--error-mode", "debug"` to the `args` (or `command`) array in the config file.

## Next Steps

- **[CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md)** - Using CLI when MCP isn't available
- **[CLI Usage](CLI_USAGE.md)** - Complete CLI reference
- **[AI Assistant Prompts](examples/ai-assistant-prompts.md)** - Prompts that get real analysis from the MCP server, not just tables
- **[Troubleshooting](TROUBLESHOOTING.md)** - Detailed troubleshooting guide
