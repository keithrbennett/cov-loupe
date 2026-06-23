# AGENTS.md – Codex Cloud Guide

[Project overview in README](README.md)

This file provides guidance to Codex, Claude Code (claude.ai/code), Gemini CLI, and any related agents when working with this repository. Treat it as the canonical reference for workflows, tooling, and expectations; update it directly whenever new agent instructions are required.

## Mission
- Pull accurate coverage data and project facts for users by driving cov-loupe tools rather than
computing it from scratch or analyzing the Simplecov-generated .resultset.json file directly.
- Keep workflow transparent: explain what you did, why it matters, and what the user should consider next.
- Leave the repository tidy; only touch files that advance the request. If you find 
other opportunities for improvement along the way, mention them in the form of a prompt the user can use later.

## Running External Commands

- When running shell commands on this project, use a Bash login shell where possible: run commands via bash -lc '<command>' (or the platform’s equivalent) rather than relying on the default shell.
- If practical, use workdir features of the agent rather than relying on `cd` in the command string

## Environment & Execution

Prefer project‑local tools and scripts (for example, bin/ scripts, package.json scripts, Makefile targets) instead of ad‑hoc one‑off commands when building, testing, or running the project.


- Prefer `rg`/`rg --files` for searches; switch only if ripgrep is unavailable.
- Sandbox: workspace write access; network is restricted. Request escalation (`with_escalated_permissions` + short justification) only when indispensable.
- Approval mode is `on-request`: retry failed-but-needed commands with escalation rather than asking the user manually.
- Planning tool: skip for trivial chores; otherwise create a multi-step plan and keep it updated as you work (max one `in_progress` step).
- When moving or renaming tracked files, use `git mv` (or `git mv -k`) instead of plain `mv` so history stays intact.

## Ruby Guidelines
- Use the project's Ruby version.
- Prefer `bundle exec` for project tools.
- Prefer binstubs when present:
  - `bin/rake`
  - `bin/rspec`
  - `bin/rubocop`
- Before editing, inspect:
  - `Gemfile`
  - `Gemfile.lock`
  - `*.gemspec`
  - `.rubocop.yml`
  - `.rspec`
- Run the smallest relevant test first.
- Preserve existing Ruby idioms.
- Do not add gems unless necessary.
- If `ruby-lsp` is available, prefer symbol-aware analysis over broad file dumping when the tool supports that workflow.

## Repository Snapshot
- Ruby gem exposing a SimpleCov coverage CLI (`exe/cov-loupe`) and MCP server; library lives under `lib/cov_loupe/`.
- Key files: main entry point at `lib/cov_loupe.rb`, core modules in `lib/cov_loupe/` including `cli.rb`, `model/model.rb`, `mcp_server.rb`, and tool implementations in `lib/cov_loupe/tools/*.rb`.
- Tests: RSpec under `spec/` with fixtures in `spec/fixtures/`; running tests produces `coverage/.resultset.json` consumed by the tools.
- Useful commands:
  - `bundle install` – install dependencies
  - `bundle exec rspec` – run rspec (currently not working in Codex for macOS)
  - `bundle exec exe/cov-loupe ...` – run CLI or MCP server directly
  - `cov-loupe list` – table view of coverage data

## Project Overview
`cov-loupe` is a Ruby gem that ships both a CLI and an MCP (Model Context Protocol) server for inspecting SimpleCov coverage data. It reads coverage resultsets directly (SimpleCov is only loaded when multi-suite merges are required) and exposes multiple data formats: file summaries, raw line arrays, uncovered lines, per-line detail, and repo-level tables.

### Key Technologies
- **Ruby** – implementation language and packaging format (gem).
- **MCP (Model Context Protocol)** – JSON-RPC server for editor/agent integrations.
- **RSpec** – primary test framework.
- **Simplecov** - test coverage analysis tool

### Dual Mode Architecture
`CovLoupe.run` operates in either CLI mode (default) or MCP server mode (when `-m mcp` or `--mode mcp` is specified). This dual-mode entry point enables both interactive commands and background tool-serving from the same executable.

### Core Components
- `lib/cov_loupe/model/model.rb` (`CoverageModel`) – core API for querying and shaping coverage data.
- `lib/cov_loupe/cli.rb` (`CoverageCLI`) – CLI interface with subcommands like `list`, `summary`, `raw`, and more.
- `lib/cov_loupe/mcp_server.rb` (`MCPServer`) – JSON-RPC server that exposes tools to MCP clients.
- `lib/cov_loupe/tools/*.rb` – tool implementations (`file_coverage_summary`, `project_coverage`, etc.).
- Error handling utilities keep behavior context-aware (friendly CLI output, raised exceptions for libraries, structured MCP responses logged to `./cov_loupe.log`).

### Coverage Data Flow
1. Read SimpleCov `.resultset.json` files without needing SimpleCov at runtime (unless merging suites).
2. Resolve file paths using absolute match, relative path matching, and basename fallback strategies.
3. Provide coverage data in multiple formats: raw arrays, summaries, uncovered lines, per-line details, totals, and formatted tables.

## Building, Running, and Testing

### Prerequisites
- Ruby >= 3.2
- Bundler

### Installation
```sh
bundle install
```

### Running Tests
Run the full suite (and generate `coverage/.resultset.json`) with:
```sh
bundle exec rspec
```
You can also run the default Rake task:
```sh
rake
```
Use `bundle exec rspec spec/path_spec.rb` to target specific specs when needed.

### Manual Testing
- Run the CLI locally during development:
  ```sh
  bundle exec exe/cov-loupe
  ```
- Inspect help output (works whether or not the gem is installed globally):
  ```sh
  bundle exec exe/cov-loupe --help
  # or
  cov-loupe --help
  ```
- Exercise the MCP server manually by piping JSON-RPC:
  ```sh
  echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"lib/cov_loupe/model/model.rb"}}}' | bundle exec exe/cov-loupe -m mcp
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"help","arguments":{}}}' | bundle exec exe/cov-loupe -m mcp
  ```

### Building
```sh
gem build cov-loupe.gemspec
gem install cov-loupe-*.gem
```

## CLI Usage

Run `bundle exec exe/cov-loupe` for up-to-date usage information.

The `cov-loupe` executable can be run directly (`bundle exec exe/cov-loupe ...` or `cov-loupe ...` when installed). Core subcommands (with single-character abbreviations):
- `list`, `l` – show a table of all files and their coverage.
- `summary <path>`, `s` – show covered/total/percentage for one file.
- `raw <path>`, `r` – print the raw SimpleCov lines array.
- `uncovered <path>`, `u` – list uncovered line numbers.
- `detailed <path>`, `d` – show per-line hit counts and coverage status.
- `totals`, `t` – show aggregated totals for the project.
- `validate <file|-i code>`, `v` – run a Ruby predicate to enforce coverage policies.
- Use `-v` / `--version` to print the version string and exit.

## MCP Server Usage
Run `cov-loupe` in MCP mode with `-m mcp`/`--mode mcp`. You can issue JSON-RPC requests over stdio, for example:
```
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"help","arguments":{}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"file_coverage_summary","arguments":{"path":"lib/cov_loupe/model/model.rb"}}}
```
All responses are emitted as `type: "text"`; JSON objects are returned as JSON strings in the content payload so MCP clients can parse them easily.

## Prompt Examples for MCP Clients
- “What’s the coverage percentage for `lib/cov_loupe/model/model.rb`?” → call `file_coverage_summary`.
- “Which lines in `spec/fixtures/project1/lib/bar.rb` are uncovered?” → call `file_uncovered_lines`.
- "Show the repo coverage table sorted worst-first." → call `project_coverage` with `{"sort_order":"ascending"}` (default order highlights highest coverage first, worst at end).
- “List files with the worst coverage.” → call `project_coverage` (optionally `{"sort_order":"ascending"}`).
- “I’m not sure which tool applies.” → call `help`.
Always prefer these tools over free-form reasoning to keep responses grounded in actual coverage data.

## MCP Tool Playbook
- Always select an MCP tool over ad-hoc reasoning for coverage data. Unsure which one fits? Call `help`.
- Available tools: `file_coverage_summary`, `file_coverage_detailed`, `file_uncovered_lines`, `file_coverage_raw`, `project_coverage`, `project_coverage_totals`, `project_validate`, `help`, and `version`.
- Responses return deterministic JSON/text; surface the tool output directly unless the user asks for interpretation. Note that `project_coverage` now includes `skipped_files`, `missing_tracked_files`, `newer_files`, and `deleted_files` arrays in its output to report any files that could not be processed due to errors or staleness.

## Development Conventions
- Target Ruby >= 3.2; use two-space indentation and `# frozen_string_literal: true` in Ruby files.
- Match existing style and patterns (see `CoverageModel` and `CoverageCalculator` helpers). Comments should clarify non-obvious logic only.
- Never undo or overwrite user changes outside your scope; integrate with them instead. However, if the new changes would be better implemented by modifying other sections, e.g., extracting now-duplicated behavior into a special method, then do that.
- When adding behavior, couple it with tests; keep or raise coverage. Specs belong in `spec/**/*_spec.rb` mirroring the lib path.
- Validate meaningful changes with `bundle exec rspec` when feasible; note skipped verification in your summary if you cannot run it.
- The codebase follows standard Ruby conventions and emphasizes user-friendly CLI output, structured MCP responses, and rich error handling.

### Error Handling Strategy
- **CLI mode** – render user-friendly messages, respect exit codes, and support optional debug output.
- **Library mode** – raise custom exceptions for programmatic handling.
- **MCP server mode** – return structured error responses and log context to `./cov_loupe.log`.

### Path Resolution Strategy
1. Attempt exact absolute path matches within the coverage data.
2. Retry using paths without the working-directory prefix.

### Resultset Discovery
- The tool locates `.resultset.json` by checking default paths or by honoring explicit CLI/MCP arguments. See [Configuring the Resultset](README.md#configuring-the-resultset) for details.
- SimpleCov is a lazy-loaded dependency used only when multi-suite resultsets require merging.

## Git Workflow
1. **Run Tests:** Always run Rubocop and the test suite to verify your changes before considering them complete:
    ```bash
   bundle exec rubocop # and then `rubocop -A` if necessary
   bundle exec rspec
    ```
2. **Do Not Commit:** Never execute `git commit` directly. Instead, stage changes with `git add` and propose a clear, concise commit message for the user to use.
3. **Selective Staging:** Never assume that all uncommitted files are intended to be committed. Do not use `git add .` or similar catch-all commands. Explicitly stage only the files relevant to the current task.
4. **Use `--no-pager`:** When running git commands that may produce long output (e.g., `git diff`, `git log`), include `--no-pager` between `git` and the subcommand to prevent paging issues in automated environments:
   ```sh
   git --no-pager diff
   git --no-pager log --oneline
   ```
5. **Release Scripts:** The project uses `bin/pre-release-check` to automate preflight steps only. Do not flag missing automation for tagging, `git push`, or `gem push`; those are intentionally manual (e.g., MFA prompts, error handling).

## Response Expectations
- Be concise and collaborative. Lead with the change/insight; follow with necessary detail.
- Reference files with inline clickable paths (e.g., `lib/cov_loupe/model/model.rb:42`). Avoid ranges and external URIs.
- When providing content intended for the user to copy and paste (like commit messages or configuration snippets), do not include line numbers or any other decorators that would interfere with direct usage.
- Summaries use plain bullets (`-`). Offer next steps only when they flow naturally (tests, commits, builds, validation).
- Do not dump entire files; mention paths. Keep tone factual, note open questions, and highlight testing gaps.

## Testing Notes
- Run `bundle exec rspec` to generate the `coverage/.resultset.json` analyzed by the tools.
- SimpleCov loads lazily only when merging multi-suite resultsets.
- Test files live in `spec/` and follow standard RSpec conventions.
- Where possible, make tests more DRY (concise) by iterating over arrays of test setups.
- If there are test errors that would never occur in production (i.e. that are errors due to the test environment and not logic errors), the agent should modify test code and not production code, and make the solution as simple as possible.

## Troubleshooting Notes
- Coverage lookup order: The tool locates the `.resultset.json` file by checking a series of default paths or by using a path specified by the user. For a detailed explanation of the configuration options, see the [Configuring the Resultset](README.md#configuring-the-resultset) section in the main README.
- `COV_LOUPE_OPTS` can set default CLI flags (command-line arguments still win).
- Mode selection: Use `-m mcp`/`--mode mcp` to run as MCP server, or `-m cli`/`--mode cli` (or omit for default) for CLI mode.

## Rubocop Linting

Rubocop is used to enforce consistent code styling and best programming practices.
Write code consistent with Rubocop configured rules, e.g. indentation and use of
`it_behaves_like` instead of `include_examples` in RSpec.

### Sandbox Environments

If running RuboCop in a sandboxed environment (e.g., AI coding assistants with file system restrictions), you may encounter cache write failures:

```
Read-only file system @ rb_sysopen
  → /home/user/.cache/rubocop_cache/...
```

**Workaround:** Use the `--cache false` flag:
```sh
bundle exec rubocop --cache false
```

This disables caching and adds approximately 5 seconds to execution time (3s → 8s) but ensures successful analysis in sandboxed environments. See [dev/prompts/guidelines/ai-code-evaluator-guidelines.md](dev/prompts/guidelines/ai-code-evaluator-guidelines.md) for details on why caching is enabled by default.

## Documentation
- `README.md` – primary documentation for installation, CLI usage, MCP integration, troubleshooting, and resultset configuration.
- `docs/user/` – user-facing guides, examples, and troubleshooting.
- `docs/dev/` – deeper architecture notes, contributing details, and decisions.

### Migration Docs
Migration documentation must accurately reflect the state of the project at the version it describes. Do not retroactively update migration docs with changes (such as renamed methods or moved files) that did not exist in that version. Each version's migration guide should describe only the changes and APIs that were correct at the time of that release.

## Important Conventions
- Require files via `cov_loupe` paths.
- Ensure API paths work with both absolute and relative inputs.
- The executable name is `cov-loupe` (hyphenated).
- Keep CLI error messages user-friendly and MCP responses structured.
