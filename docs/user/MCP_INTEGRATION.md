# MCP Integration Guide

[Back to main README](../../README.md)

> **⚠️ Important:** The `-m mcp` (`--mode mcp`) option is **required** to run cov-loupe as an MCP server, either on the command line or in `COV_LOUPE_OPTS`. Without it, cov-loupe runs in CLI mode, prints a report, and exits, so the client never completes its MCP handshake. Configurations written for versions before 4.0 must add it; see [Migrating to v4](migrations/MIGRATING_TO_V4.md).

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
- [Stdout Must Stay Clean](#stdout-must-stay-clean)
- [Available MCP Tools](#available-mcp-tools-functions)
    - [JSON Response Format](#json-response-format)
    - [Error Responses](#error-responses)
- [Testing Your Setup](#testing-your-setup)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [Next Steps](#next-steps)

## Setup by Client

> **Tip:** If you use RVM, or see `Resolving dependencies...` printed before the MCP handshake, set up [the launch wrapper](#step-by-step-the-launch-wrapper) before configuring a client; with RVM you may need an absolute path in it (see its step 1). The wrapper prevents a common startup failure in every client below and every project. Settling a project's bundle also works, but only for that project; see [Recommended Launch Patterns](#recommended-launch-patterns).

> **Note:** These instructions are a starting point, not a verified reference. Not every client has been fully tested, and these tools change quickly, so commands and file locations may have changed. If something doesn't work, check your client's own documentation (e.g., `claude mcp --help`, `codex mcp --help`, `agy mcp --help`, `opencode mcp --help`).

> **Note:** A one-shot, non-interactive test (for example, running your client with `-p` or `exec`) can fail even when the server works: nobody is there to answer the client's permission prompt for the MCP tool call, so the call is blocked or denied. Pre-authorize the tool in your client's settings, or test interactively. See also [Confirm the server actually starts](#confirm-the-server-actually-starts).

### Claude Code

`mcp add` takes the display name, then the executable, then `--` and the executable's arguments. If `cov-loupe` is on your `PATH`, its name is enough; otherwise give its full path (e.g. `/a/b/cov-loupe`).

```sh
# Add the MCP server (the default scope is local)
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

`mcp add` takes the display name, then `--`, then the executable and its arguments. If `cov-loupe` is on your `PATH`, its name is enough; otherwise give its full path (e.g. `/a/b/cov-loupe`).

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

**Warning:** `codex mcp remove cov-loupe` deletes the `env_vars` line along with the rest of the section, so after running `codex mcp add` again you must add it back by hand. To avoid this, edit `~/.codex/config.toml` directly instead of using `remove` and `add`.

**Watch the position of `--`.** It goes right after the server name and *before* the command: `codex mcp add cov-loupe -- cov-loupe -m mcp` (name, `--`, command, arguments). If you put the command before the `--`, as in `codex mcp add cov-loupe cov-loupe -- -m mcp`, Codex stores the `--` as a literal argument: `args = ["--", "-m", "mcp"]`, and `cov-loupe` fails with `'--' is allowed only after a subcommand`. After adding, confirm that the `Args` column of `codex mcp list` shows `-m mcp` with no leading `--`.

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
cursor-agent mcp list-tools cov-loupe    # starts the server and lists its 8 tools (9 with --allow-code-predicates); no model needed
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

Pi 0.99.0 and later include built-in MCP support. Add the server with:

```sh
pi mcp add cov-loupe -- cov-loupe -m mcp
pi mcp list   # verify the connection
```

This writes the user-level `~/.pi/agent/mcp.json`. Add `-l` (`pi mcp add -l cov-loupe -- cov-loupe -m mcp`) to write the project's `.pi/mcp.json` instead; Pi reads project configuration only after you trust the project. Either file uses the standard format:

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

Inside Pi, `/mcp` shows connection status, and `/reload` picks up servers added or changed outside the session. To remove the server, run `pi mcp remove cov-loupe` (add `-l` for the project file).

Older Pi versions need the community [`pi-mcp-adapter`](https://github.com/nicobailon/pi-mcp-adapter) extension instead (`pi install npm:pi-mcp-adapter`); see its README for configuration.

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

## Stdout Must Stay Clean

MCP over stdio is strict: the server must not print anything to `stdout` before the MCP handshake begins. Any banner, warning, dependency-resolution message, or debug output written before that point can cause the client to reject startup or report a handshake failure.

The rule holds for the server's whole lifetime: stdout carries only JSON-RPC messages. A `project_validate` predicate that prints with `puts` writes to stdout and can break the connection; have predicates write diagnostics to `$stderr`.

When `cov-loupe -m mcp` is launched through a RubyGems-installed stub, wrapper layers can inspect the current directory's `Gemfile` before `cov-loupe` itself starts. In projects with no lockfile, missing gems, or an otherwise unsettled bundle, that can print text such as `Resolving dependencies...` and corrupt MCP startup.

For root-cause details, diagnostic commands, and the upstream RVM tracking issue, see [RubyGems Wrapper Prints to Stdout Before MCP Startup](TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup).

### Recommended Launch Patterns

If startup prints text before the handshake, try these in order. Step 1 fixes one project at a time; with RVM, or if you use cov-loupe in many projects, go straight to step 2.

1. **Settle the project's bundle.** Run `bundle install` in the project, confirm that `Gemfile.lock` exists and `bundle check` succeeds, then restart the client, or run the manual test in [Testing Your Setup](#manual-testing-via-command-line). This fixes one project.
2. **Use the launch wrapper.** A small shell script that exports `NOEXEC_DISABLE=1` before calling `cov-loupe -m mcp` works in every project, whatever the state of its bundle. This is the most reliable fix for RVM and similar environments. See [Step by Step: The Launch Wrapper](#step-by-step-the-launch-wrapper).
3. **Bypass the RubyGems wrapper.** Invoke the gem's real executable directly; [Troubleshooting](TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup) shows how to find its path, and why under RVM it also needs `GEM_HOME` and `GEM_PATH`.

For local development from a checkout, point the MCP client directly at the checkout's [`exe/cov-loupe`](https://github.com/keithrbennett/cov-loupe/blob/main/exe/cov-loupe).

### Step by Step: The Launch Wrapper

Set this up once, and it works in every project directory, whether or not the project's bundle is settled.

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

The script finds `cov-loupe` on the `PATH` the client gives it. If your client doesn't pass your shell's Ruby setup (common with RVM), startup fails with `exec: cov-loupe: not found`; replace `cov-loupe` in the `exec` line with an absolute path that works without that setup, such as the one `rvm wrapper show cov-loupe` prints. See [Path Issues with Version Managers](TROUBLESHOOTING.md#path-issues-with-version-managers).

**2. Check that it works.** You should see a JSON line and nothing else before it:

```sh
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe-no-bundler
```

This runs in your shell, so it can't catch a client that lacks your Ruby setup; see the note under step 1.

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

If a client can't find the script itself (some launch servers with a minimal `PATH`), register the script's absolute path instead, e.g. `/home/you/.local/bin/cov-loupe-no-bundler`.

`NOEXEC_DISABLE=1` turns off the `rubygems-bundler` hook that RVM installs, which is what prints `Resolving dependencies...` to `stdout`. It doesn't change what `cov-loupe` does.

See [Troubleshooting](TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup) for wrapper examples and direct-executable fallback configuration.

## Available MCP Tools (Functions)

### Tool Catalog

cov-loupe exposes 8 MCP tools by default, and 9 when started with `--allow-code-predicates`. For each tool's CLI equivalent, see [CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md#mcp-tools-and-cli-subcommands).

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `file_coverage_summary` | File coverage summary | `path` |
| `file_coverage_detailed` | Per-line coverage | `path` |
| `file_coverage_raw` | SimpleCov's unprocessed hit-count array | `path` |
| `file_uncovered_lines` | List uncovered lines | `path` |
| `project_coverage` | Project-wide coverage (JSON, table, YAML, etc.) | `sort_order`, `file_globs`, `format` |
| `project_coverage_totals` | Aggregated line totals | `file_globs` |
| `project_validate` | Validate coverage policies (only with `--allow-code-predicates`) | `code` or `file` |
| `help` | Tool discovery | (only the common `output_chars`) |
| `version` | Version information | (only the common `output_chars`) |

### JSON Response Format

For tools that return structured data, `cov-loupe` serializes the data as a JSON string and returns it inside a `text` part of the MCP response. The exceptions are `version`, which returns plain text such as `CovLoupe version: X.Y.Z`, and `project_coverage` with a `format` other than `json` or `pretty_json`, which returns YAML, a table, or Ruby-rendered text instead.
Successful structured payloads begin with integer `schema_version`. Library coverage hashes carry the same field. The [shipped JSON Schemas](https://github.com/keithrbennett/cov-loupe/tree/main/lib/cov_loupe/schemas/v1) define the payloads; see [Schema Version](LIBRARY_API.md#schema-version) for schema lookup and compatibility rules. Check `result.isError` before parsing the content.

**Example:**
```json
{
  "type": "text",
  "text": "{\n  \"schema_version\": 1,\n  \"file\": \"lib/foo.rb\",\n  \"covered\": 2,\n  \"uncovered\": 1,\n  \"total\": 3,\n  \"percentage\": 66.66,\n  \"stale\": \"ok\"\n}"
}
```

Whitespace varies by tool. The file tools, `project_coverage_totals`, and `project_validate` return indented JSON. `help` and `project_coverage` with the default `format: json` return it on one line, and `project_coverage` with `format: pretty_json` returns it indented. Parse the JSON rather than relying on its layout. For why the JSON is sent as text rather than as a `resource` part, see the [architecture decision](../dev/arch-decisions/application-architecture.md#mcp-responses-as-text-content).

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
        "text": "{\"schema_version\":1,\"tools\":[{\"tool\":\"file_coverage_summary\",...}]}"
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
        "text": "Error: Coverage data error: No coverage entry found for /path/to/project/nonexistent.rb"
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
| `-S`, `--raise-on-stale BOOLEAN` | ✅ Default | `raise_on_stale` | Request param overrides; CLI sets default (`false` or `true`) |
| `-g`, `--file-globs` | ✅ Default | `file_globs` | Request param overrides; CLI sets default (array). Accepted per request only by `project_coverage` and `project_coverage_totals`; a server-level `-g` is also the default for the model `project_validate` predicates receive |
| `--error-mode` | ✅ Yes | N/A | Sets server-wide error handling (cannot override per tool) |
| `-l`, `--log-file` | ✅ Yes | N/A | Sets server log location (cannot override per tool) |
| `-O`, `--output-chars` | ✅ Default | `output_chars` | Request param overrides; CLI sets default (`default`, `fancy`, or `ascii`) |
| `-f`, `--format` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-o`, `--sort-order` | ❌ No | N/A | CLI flag ignored in MCP; pass `sort_order` per `project_coverage` tool call |
| `-s`, `--source` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-n`, `--context-lines` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-C`, `--color BOOLEAN` | ❌ No | N/A | CLI-only presentation flag (not used by MCP) |
| `-m`, `--mode` | ✅ Required | N/A | **Required for MCP mode:** `-m mcp` or `--mode mcp`. Default: `cli`. |
| `--[no-]allow-code-predicates` | ✅ Yes | N/A | Registers `project_validate`, which runs client-supplied Ruby (see [Policy Validation Tools](#policy-validation-tools)). Default: off; `--no-allow-code-predicates` overrides a `COV_LOUPE_OPTS` setting. |

**Summary:**

- **Server-level options** (`--error-mode`, `--log-file`, `--allow-code-predicates`) are set once when the server starts and apply to every tool call.
- **Tool-level options** (`root`, `coverage_file`, `raise_on_stale`, `file_globs`, `output_chars`) set defaults that a tool call's arguments override. Only the two project coverage tools accept `file_globs` per call, but a server-level `-g` also applies to the `model.list` and `model.project_totals` calls of `project_validate` predicates.
- **CLI-only options** (`-f`, `-o`, `-s`, `-n`, `-C`) never reach the MCP server. To change the sort order, pass `sort_order` in each `project_coverage` call.

**Precedence for MCP tool config:** tool-call argument > CLI options used to start the server (including `COV_LOUPE_OPTS`) > built-in defaults (`root: '.'`, `raise_on_stale: false`, `coverage_file: nil`, and `file_globs: []`, which means no filtering and no check for files missing from the coverage data).

**Data caching:** The server caches coverage data in a process-wide cache (`ModelDataCache`), shared by all `CoverageModel` instances that use the same coverage file and root. When the coverage file changes (detected by its file signature and MD5 digest), the cache reloads it. A new, lightweight model instance is created for each tool request.

### Common Parameters

The file tools and the project tools (`project_coverage`, `project_coverage_totals`, `project_validate`) accept these parameters in the JSON request (`help` and `version` take only `output_chars`):

- `path` (file tools only, where it is required) - File path (relative or absolute); the project tools reject it
- `root` (optional) - Project root directory (default: the server's `--root`, which is `.` unless set)
- `coverage_file` (optional) - Path to the `coverage.json` file, or to a directory containing one. See [Configuring the Coverage File](../../README.md#configuring-the-coverage-file) for details.
- `raise_on_stale` (optional) - Raise error on staleness (and, for the project tools, on a file matching the file globs that is not in coverage data or a skipped coverage row): `false` or `true` (default: the server's `--raise-on-stale`, which is `false` unless set)
- `output_chars` (optional) - Output character mode: `"default"`, `"fancy"`, or `"ascii"` (short codes: `d`, `f`, `a`). `"ascii"` draws table borders with ASCII characters and escapes non-ASCII as `\uXXXX` in successful JSON payloads. Data is never changed, so error results and non-JSON formats can contain non-ASCII characters. See [`--output-chars`](CLI_USAGE.md#output-chars).

`project_coverage` and `project_coverage_totals` also accept `file_globs` (an array of glob patterns). `project_validate` does not accept it, but its predicates' model uses a server-level `-g` as its default. `project_coverage` additionally accepts `sort_order` (`"ascending"` or `"descending"`; short codes: `a`, `d`) and `format` (`"json"`, `"pretty_json"`, `"yaml"`, `"amazing_print"`, `"inspect"`, `"puts"`, `"pretty_print"`, `"table"`; short codes: `j`, `J`, `y`, `a`, `i`, `p`, `P`, `t`).

### Tool Details

#### Per-File Tools

These tools analyze individual files. All require `path` parameter. `file_coverage_summary`,
`file_uncovered_lines` and `file_coverage_detailed` return the same line metrics as top-level keys:
`covered`, `uncovered` (a count), `total` (coverable lines), and `percentage`, which is `null` when a
file has no coverable lines (for example, a file containing only comments).

**`file_coverage_summary`** - Covered/total/percentage summary
```json
{"schema_version": 1, "file": "...", "covered": 12, "uncovered": 2, "total": 14, "percentage": 85.71, "stale": "ok"}
```

**`file_uncovered_lines`** - List uncovered line numbers
```json
{"schema_version": 1, "file": "...", "uncovered_lines": [5, 9, 12], "covered": 11, "uncovered": 3, "total": 14, "percentage": 78.57, "stale": "ok"}
```

**`file_coverage_detailed`** - Per-line hit counts
```json
{"schema_version": 1, "file": "...", "lines": [{"line": 1, "hits": 1, "covered": true}, ...], "covered": 12, "uncovered": 2, "total": 14, "percentage": 85.71, "stale": "ok"}
```

**`file_coverage_raw`** - Raw SimpleCov per-line hit counts
```json
{"schema_version": 1, "file": "...", "line_hits": [1, 0, null, 5, 2, null, 1], "stale": "ok"}
```
Lines SimpleCov marked `"ignored"` (excluded with `nocov` blocks or directive comments) are returned as `null` and, like other `null` lines, are not counted in covered or total lines or in percentages.

**Staleness values:** `"ok"` (fresh), `"deleted"` (source file deleted), `"newer"` (source file modified after the coverage run), `"length_mismatch"` (line count differs from the coverage data), `"unreadable"` (source could not be read, or its staleness check failed)

#### Project-Wide Tools

**`project_coverage`** - Coverage for all files in various formats

- Parameters: the [common parameters](#common-parameters), plus `sort_order` (`ascending`|`descending`, default `descending`), `file_globs` (array), `format` (`json`|`pretty_json`|`yaml`|`amazing_print`|`inspect`|`puts`|`pretty_print`|`table`)
- Default format: `json`
- Returns (format dependent):
    - `json`/`pretty_json`: a JSON object. `yaml`/`amazing_print`/`inspect`/`puts`/`pretty_print`: the same data rendered in that format, not JSON. The data is `{"schema_version": 1, "files": [...], "skipped_files": [...], "not_in_coverage_files": [...], "newer_files": [...], "deleted_files": [...], "length_mismatch_files": [...], "unreadable_files": [...], "timestamp_status": "ok|missing", "warnings": [...]}`.
    - `warnings` is present only when `timestamp_status` is `"missing"` or [most files were not found under the project root](TROUBLESHOOTING.md#the-project-root-may-be-wrong).
    - Table: Plain text table with box-drawing characters (ASCII with `output_chars: "ascii"`), followed by any exclusion, timestamp, skipped-row, and wrong-root warnings
    - Each entry in `files` is `{"file", "covered", "uncovered", "total", "percentage", "stale"}`, the same shape as a `file_coverage_summary` result without `schema_version`; `percentage` is `null` when the file has no coverable lines (shown as `n/a` in the table).

**`project_coverage_totals`** - Aggregated line totals

- Parameters: the [common parameters](#common-parameters), plus `file_globs` (array)
- Returns: `{"schema_version":1,"covered":N,"uncovered":N,"total":N,"percentage":Float|null,"file_globs":[String],"file_counts":{"total":N,"with_coverage":{"total":N,"ok":N,"stale":{"total":N,"by_type":{"deleted":N,"newer":N,"length_mismatch":N,"unreadable":N}}},"without_coverage":{"total":N,"by_type":{"not_in_coverage":N|null,"skipped":N}}},"timestamp_status":"ok|missing","warnings":[String]}`
- The line metrics count fresh files only; `file_counts.with_coverage.ok` is how many.
- `without_coverage` is always present. Its `not_in_coverage` count is `null` when no file globs are set, since there is then no list of files to check.
- `warnings` is present when `timestamp_status` is `"missing"` or [most files were not found under the project root](TROUBLESHOOTING.md#the-project-root-may-be-wrong).

#### Policy Validation Tools

**`project_validate`** - Validate coverage against custom policies

The server registers `project_validate` only when started with `--allow-code-predicates`, for example `"args": ["-m", "mcp", "--allow-code-predicates"]`. Without the flag, the tool is absent from `tools/list` and `help`, and calling it returns a JSON-RPC `-32602` ("Invalid params") error whose `data` is `"Tool not found: project_validate"`.

It is off by default because the predicate is Ruby written by the MCP client, usually an LLM, and the user may never see it. The server runs as its own process, outside any shell sandbox or command-approval prompts the client applies, so a client steered by prompt injection could run arbitrary code with your privileges. Enable it only if you accept that risk, for example on a large project where a predicate's single Boolean is far smaller than the `project_coverage` output an LLM would otherwise have to read. Clients that have a shell can run `cov-loupe validate` instead, which goes through the client's usual command controls.

- Parameters: Either `code` (Ruby string) OR `file` (path to Ruby file; a relative path is resolved against `root`, unlike the CLI's `validate`, which resolves it against the current directory), plus optional `root`, `coverage_file`, `raise_on_stale`, `output_chars`. A predicate must not print to stdout, which carries the MCP protocol; use `$stderr`
- Returns: `{"schema_version": 1, "result": Boolean}`. The predicate's return value is coerced by truthiness (as in the CLI exit code), so `result` is always a Boolean; a false result still has `isError: false` because the tool call succeeded.
- Execution errors (syntax error in the predicate, missing predicate file, etc.) return `isError: true` with the friendly error message in `content`
- Security Warning: Predicates execute as arbitrary Ruby code with full system privileges. Only use predicate files from trusted sources.
- Examples:
    - Check if all files have at least 80% coverage: `{"code": "->(m) { m.list['files'].all? { |f| f['percentage'].nil? || f['percentage'] >= 80 } }"}`
    - Run coverage policy from file: `{"file": "coverage_policy.rb"}`

#### Utility Tools

**`help`** - Tool discovery and canonical resource values
**`version`** - Version information

`help` returns:

- `tools` - guidance for each available MCP tool other than `help` itself (`tool`, `label`, `use_when`, `avoid_when`, `inputs`)
- `resources` - canonical shared resource values:
    - `repo` (public GitHub URL)
    - `docs` (public docs URL)
    - `docs_local` (absolute path to local README; the CLI spells it `--path-for docs-local`)

Example `help` payload excerpt:
```json
{
  "schema_version": 1,
  "resources": {
    "repo": "https://github.com/keithrbennett/cov-loupe",
    "docs": "https://keithrbennett.github.io/cov-loupe/",
    "docs_local": "/abs/path/to/README.md"
  }
}
```

For prompts that go beyond tables and counts, see [AI Assistant Prompts](examples/ai-assistant-prompts.md).

## Testing Your Setup

### Manual Testing via Command Line

Use these commands as smoke tests to confirm that the MCP server is installed, launches with your configuration, and responds to JSON-RPC over stdio. They are not an exhaustive error-contract test suite; the included error cases are optional sanity checks. See [Error Responses](#error-responses) for the full MCP failure model.

```sh
# Prefer the real executable or a known-clean working directory for MCP tests.
# Test version tool (simplest, no parameters needed)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp

# Test help tool (no parameters needed)
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"help","arguments":{}}}' | cov-loupe -m mcp

# Test summary tool: run from your project root, replacing lib/my_app/order.rb with a file in your coverage
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"lib/my_app/order.rb","root":"."}}}' | cov-loupe -m mcp

# Optional error sanity check: the response should contain a `result` with `isError: true`
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"nonexistent.rb","root":"."}}}' | cov-loupe -m mcp

# Optional validation sanity check: this also returns a `result` with `isError: true`
echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{}}}' | cov-loupe -m mcp

# Test with a project-specific root
echo '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"app/models/order.rb","root":"docs/fixtures/demo_project"}}}' | cov-loupe -m mcp
```

**Important Notes:**

- JSON-RPC messages must be on a single line. Multi-line JSON will cause parse errors.
- CLI flags like `-R` set server defaults, but per-request JSON parameters still win.
- The `root` parameter is optional and defaults to the server's `--root` (`.` unless set).
- The `docs/fixtures/demo_project` example above must run from the root of a cov-loupe checkout. It uses a committed fixture whose coverage timestamp is deliberately set far in the future, so its responses are reproducible on a fresh clone.
- If you see text such as `Resolving dependencies...` before the JSON-RPC response, your launcher polluted `stdout` before MCP startup. See [Stdout Must Stay Clean](#stdout-must-stay-clean).

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

A server can be registered and still fail to start, and most `list` commands only read the configuration:

- `claude mcp list` (shows `✔ Connected`), `opencode mcp list` (shows `connected`), and `cursor-agent mcp list` (shows `ready`, once approved) do try to start the server.
- `codex mcp list`, `agy mcp list`, and Kimi's config do not, so `enabled` there proves nothing.

To be sure, make a real request. Run these non-interactive checks from a project directory. Most call the `version` tool once; compare the answer with `cov-loupe --version`. The Copilot and Cursor rows instead check the connection log or the tool list:

| Client | Command |
|--------|---------|
| Claude Code | `claude -p "Call the cov-loupe MCP version tool and reply with only the version." --allowedTools mcp__cov-loupe__version` |
| Codex | `codex exec -c 'mcp_servers.cov-loupe.tools.version.approval_mode="approve"' "Call the cov-loupe MCP version tool (not the shell) and reply with only the version."` |
| GitHub Copilot CLI | `copilot -p "hi" --log-level debug --log-dir /tmp/copilot-logs`, then `grep cov-loupe /tmp/copilot-logs/*` and look for `MCP client for cov-loupe connected` |
| Cursor | `cursor-agent mcp list-tools cov-loupe` (after `cursor-agent mcp enable cov-loupe`); lists the tools without using a model |
| Kimi Code | `kimi -p "Call the cov-loupe MCP version tool and reply with only the version."` |
| OpenCode | `opencode run -m <provider/model> "Call the cov-loupe MCP version tool and reply with only the version."` |
| Pi | `pi -p "Call the cov-loupe MCP version tool and reply with only the version."` |

A model that can't reach the server may still answer, using the shell or a guess. If the version doesn't match `cov-loupe --version`, or the client didn't report a tool call to `cov-loupe`, treat it as a failure.

### Checking Logs

The MCP server logs tool-execution errors and other cov-loupe diagnostics to `stderr` by default. Argument-validation failures, which the MCP SDK reports before cov-loupe runs, do not reach this logger. See [Log file initialization and target testing](LOGGING.md#log-file-initialization-and-target-testing) for how file targets are checked at startup.

```sh
# Watch an explicitly configured file in real-time
tail -f /path/to/your-configured-log-file.log

# View recent errors from an explicitly configured file
grep ERROR /path/to/your-configured-log-file.log | tail -20
```

To log to a file, add `--log-file` (or `-l`) to the server's arguments in your MCP client configuration, for example `-l /path/to/logfile.log`. Use `-l stderr` to name standard error explicitly, or `-l off` to disable logging entirely (a cross-platform alternative to `/dev/null`).

**Warning:** Explicit log files may grow unbounded in long-running or CI usage. cov-loupe does not rotate them; use external rotation or periodically clean them up.

**Note:** Logging to `stdout` is not permitted in any mode, because it would corrupt command output or the MCP JSON-RPC protocol.

## Troubleshooting

### CLI Fallback

If the MCP server doesn't work, the agent can run the CLI directly with `-fJ` (pretty JSON output).

See the **[CLI Fallback for LLMs Guide](CLI_FALLBACK_FOR_LLMS.md)** for a prompt to give your LLM and a mapping of each MCP tool and argument to its CLI subcommand and option. The [CLI Usage Guide](CLI_USAGE.md) has the full command reference and JSON output examples.

### Common Issues

**Server Won't Start**
```sh
which cov-loupe     # Verify executable exists
ruby -v             # Check Ruby >= 3.3
cov-loupe --version   # Test basic functionality
```

**Server fails only in some project directories**

If `cov-loupe -m mcp` works in one repo but fails in another, especially with text like `Resolving dependencies...` appearing before the MCP handshake, see [Stdout Must Stay Clean](#stdout-must-stay-clean). This usually means the RubyGems launcher consulted the current directory's `Gemfile` and Bundler printed to `stdout` before the MCP server started. The first fix to try is `bundle install` in that repo, followed by another normal startup attempt.

**Tools Not Appearing**

1. Restart AI assistant after config changes
2. Check the MCP host's captured stderr, or the explicitly configured log file.
3. Try explicit tool names in prompts
4. Verify MCP server status in assistant

**JSON-RPC Parse Errors**

- Ensure JSON is on a single line (no newlines)
- Test manually: `echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"help","arguments":{}}}' | cov-loupe -m mcp`

## Advanced Configuration

### Enable Debug Logging

For troubleshooting, add `--error-mode debug` to the server's arguments. How you change an existing entry depends on the client:

- **Claude Code** refuses to add a name that is already registered in the same scope, so remove the entry first, then add it again. Pass the entry's scope (`local`, `user`, or `project`, as `claude mcp get cov-loupe` shows) to both commands; without `--scope`, `add` creates a `local` entry, so a user-wide or shared project server would become visible only in the current project:
  ```sh
  claude mcp get cov-loupe   # note the Scope line
  claude mcp remove --scope user cov-loupe
  claude mcp add --scope user cov-loupe cov-loupe -- -m mcp --error-mode debug
  ```
- **Codex:** edit `~/.codex/config.toml` and add the option to `args`, for example `args = ["-m", "mcp", "--error-mode", "debug"]`. Don't re-run `codex mcp add`: it replaces the entry and drops the `env_vars` line described in the [Codex](#codex) section.
- **Antigravity:** `agy mcp add cov-loupe cov-loupe -- -m mcp --error-mode debug` updates the entry in place, but drops any `--env` values it had. Pass them again, before the name: `agy mcp add --env NAME=value cov-loupe cov-loupe -- -m mcp --error-mode debug`.
- **Every other client:** edit the server's entry in its config file and add `"--error-mode", "debug"` to the `args` array, or to the `command` array where the command is an array. The files are named in each client's section above; Gemini CLI uses `.gemini/settings.json` (project) or `~/.gemini/settings.json` (user). For VS Code servers added with `code --add-mcp`, open the user file with the `MCP: Open User Configuration` command. Cursor resets its approval when an entry changes, so run `cursor-agent mcp enable cov-loupe` again afterward.

If you use the [launch wrapper](#step-by-step-the-launch-wrapper), add the option to the wrapper's arguments the same way; it forwards them to `cov-loupe`.

## Next Steps

- **[CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md)** - Using CLI when MCP isn't available
- **[CLI Usage](CLI_USAGE.md)** - Complete CLI reference
- **[AI Assistant Prompts](examples/ai-assistant-prompts.md)** - Prompts that get real analysis from the MCP server, not just tables
- **[Troubleshooting](TROUBLESHOOTING.md)** - Detailed troubleshooting guide
