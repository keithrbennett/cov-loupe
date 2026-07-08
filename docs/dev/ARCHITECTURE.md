# Architecture

[Back to main README](../index.md) | [Architecture Decision Records](arch-decisions/README.md)

cov-loupe is organized around a single coverage data model that feeds three delivery channels: a command-line interface, an MCP server for LLM agents, and a light-weight Ruby API. The codebase is intentionally modular—shared logic for loading, normalizing, and validating SimpleCov data lives in `lib/cov_loupe/`, while adapters wrap that core for each runtime mode.

## Runtime Entry Points

- **Executable** – `exe/cov-loupe` bootstraps the gem, enforces Ruby >= 3.2, and delegates to `CovLoupe.run(ARGV)`.
- **Mode Negotiation** – `CovLoupe.run` inspects environment defaults from `COV_LOUPE_OPTS` and parses the `-m/--mode` flag. It defaults to CLI mode and instantiates `CovLoupe::CoverageCLI`. When `-m mcp` or `--mode mcp` is specified, it instantiates `CovLoupe::MCPServer` for MCP protocol communication over STDIO.
- **Embedded Usage** – Applications embed the gem by instantiating `CovLoupe::CoverageModel` directly, optionally wrapping work in `CovLoupe.with_context` to install a library-oriented error handler.

## Coverage Data Pipeline

1. **Resultset discovery** – The tool locates the `.resultset.json` file by checking a series of default paths or by using a path specified by the user. For a detailed explanation of the configuration options, see the [Configuring the Resultset](../index.md#configuring-the-resultset) section in the main README.
2. **Parsing and normalization** – `CoverageModel` loads the chosen resultset once, extracts all test suites that expose `coverage` data (e.g., "RSpec", "Minitest"), merges them if multiple suites exist, and maps all file keys to absolute paths anchored at the configured project root. Timestamps are cached for staleness checks. SimpleCov is a runtime dependency and is loaded when multi-suite merges are required.
3. **Path relativizing** – `PathRelativizer` (powered by the centralized `PathUtils` module) produces relative paths for user-facing payloads without mutating the canonical data. Tool responses pass through `CoverageModel#relativize` before leaving the process.
4. **Derived metrics** – `CoverageCalculator.summary`, `CoverageCalculator.uncovered`, and `CoverageCalculator.detailed` compute coverage stats from the raw `lines` arrays. `CoverageModel` exposes `summary_for`, `uncovered_for`, `detailed_for`, and `raw_for` helpers that wrap these calculations.
5. **Staleness detection** – `StalenessChecker` compares source mtimes/line counts to coverage metadata. CLI flags and MCP arguments can promote warnings to hard failures (`--raise-on-stale true`) or simply mark rows as stale for display.

## Interfaces

### CLI (`CovLoupe::CoverageCLI`)

- Builds on Ruby’s `OptionParser`, with global options such as `--resultset`, `--raise-on-stale`, `-fJ`, and `--source` modes.
- Subcommands (`list`, `summary`, `raw`, `uncovered`, `detailed`, `totals`, `validate`) translate to calls on `CoverageModel`.
- **Subcommand Abbreviations** – Frequent CLI users can use single-character abbreviations for most subcommands: `l` (list), `s` (summary), `u` (uncovered), `d` (detailed), `r` (raw), `t` (totals), and `v` (validate). `version` has no abbreviation to avoid confusion with the common `-v` flag.
- Uses `ErrorHandlerFactory.for_cli` to convert unexpected exceptions into friendly user messages while honoring `--error-mode`.
- Formatting logic (tables, JSON) lives in the model to keep presentation consistent with MCP responses.

### MCP Server (`CovLoupe::MCPServer`)

- Assembles a list of tool classes and mounts them in `MCP::Server` using STDIO transport.
- Relies on the same core model; each MCP request creates a fresh `CoverageModel` instance, but the underlying coverage data is cached in a global `ModelDataCache` singleton. The cache automatically reloads when the resultset file changes (validated via file signature: mtime, subsecond mtime, size, inode, and MD5 digest).
- Configuration precedence in MCP: per-request JSON parameters override CLI arguments passed when the server starts (including `COV_LOUPE_OPTS`), which in turn override built-in defaults.
- Error handling delegates to `BaseTool.handle_mcp_error`, which swaps in the MCP-specific handler and emits `MCP::Tool::Response` objects flagged with `isError: true` for tool failures.

### Library API

- Consuming code instantiates `CoverageModel` directly for fine-grained control over coverage queries.
- Use `CovLoupe::ErrorHandlerFactory.for_library` together with `CovLoupe.with_context` when an embedded caller wants to suppress CLI-friendly error logging.

## MCP Tool Stack

- `CovLoupe::BaseTool` centralizes JSON schema definitions, error conversion, and response serialization for the MCP protocol.
- Individual tools reside in `lib/cov_loupe/tools/` and follow a consistent shape: define an input schema, call into `CoverageModel`, then serialize via `respond_json`. Examples include `ProjectCoverageTool`, `FileCoverageSummaryTool`, and `FileUncoveredLinesTool`.
- Tools are registered in `CovLoupe::MCPServer::TOOLSET`. Adding a new tool requires creating a subclass and appending it to that list.

## Error Handling & Logging

- Custom exceptions under `lib/cov_loupe/errors/errors.rb` capture context for configuration issues, missing files, stale coverage, and general runtime errors. Each implements `#user_friendly_message` for consistent UX.
- `CovLoupe::ErrorHandler` encapsulates logging and severity decisions. Modes (`:off`, `:log`, `:debug`) control whether errors are recorded and whether stack traces are included.
- Runtime configuration (error handlers, log destinations) flows through `CovLoupe::AppContext`. Entry points push a context with `CovLoupe.with_context`, which stores the active configuration in a thread-local slot (`CovLoupe.context`). Nested calls automatically restore the previous context when the block exits, ensuring isolation even when multiple callers share a process or thread.
- Two helper accessors clarify intent:
    - `CovLoupe.default_log_file` / `default_log_file=` adjust the baseline log sink that future contexts inherit.
    - `CovLoupe.active_log_file` / `active_log_file=` mutate only the current context (or create one on demand) so the change applies immediately without touching the default.
- `ErrorHandlerFactory` wires the appropriate handler per runtime: CLI, MCP server, or embedded library, each of which installs its handler inside a fresh `AppContext` before executing user work.
- Diagnostics are written through `CovLoupe::Logger` to `cov_loupe.log` in the current directory by default; override with CLI `--log-file`, set `CovLoupe.default_log_file` for future contexts, or temporarily tweak `CovLoupe.active_log_file` when a caller needs a different destination mid-run. `stdout` is never a valid log destination because it would corrupt command output.

## Output Character Mode

cov-loupe provides a global output character mode that controls ASCII vs Unicode output across both CLI and MCP interfaces. This feature ensures compatibility with terminals and systems that cannot display Unicode characters while providing rich Unicode output (box-drawing characters, fancy tables) for environments that support it.

### Configuration

- **CLI flag** – `-O/--output-chars MODE` accepts `default`, `fancy`, or `ascii` (case-insensitive, with short forms `d`, `f`, `a`)
- **MCP parameter** – Optional `output_chars` parameter in tool requests overrides server default
- **Mode resolution** – `:default` resolves at runtime: UTF-8 terminal capability check for fancy, otherwise ASCII

### Implementation

- **Core conversion** – `OutputChars.convert` uses an internal transliteration map with `?` fallback for characters without ASCII equivalents
- **Charsets** – Separate charset definitions for fancy (Unicode box-drawing) and ASCII modes
- **Formatters** – All formatters (JSON, YAML, AmazingPrint, tables, source) respect the output_chars parameter
    - JSON uses `JSON.generate(..., ascii_only: true)` for ASCII mode
    - YAML and AmazingPrint post-process output through `OutputChars.convert`
    - Tables use appropriate charset and convert cell contents
    - Source output uses ASCII-safe markers (`+/X` instead of Unicode `✓/X`)

### Scope of Conversion

**Converted in ASCII mode:**
- CLI error messages and option parser errors
- Staleness error messages and file paths
- Command literal strings (via `convert_text` helper in BaseCommand)
- MCP tool JSON responses (via `respond_json` with `ascii_only: true`)
- All formatted output (tables, source, JSON, YAML)

**Not converted in ASCII mode:**
- **Log files** – Preserved in original encoding for debugging fidelity. Log files are system/debugging artifacts, not user-facing output. Converting would lose exact file paths and error details needed for troubleshooting, create inconsistency between logged paths and actual filesystem paths, and provides no user value since logs are developer artifacts.
- **Gem post-install message** – Intentionally left unchanged per requirements

### Testing

Comprehensive test coverage exists:
- Mode resolution and normalization tests
- Formatter tests for ASCII mode (JSON, YAML, AmazingPrint, tables, source)
- CLI option parsing tests for `--output-chars` flag
- MCP tool output mode tests
- Staleness error message tests with Unicode file paths

## Configuration Surface

- **Environment defaults** – `COV_LOUPE_OPTS` applies baseline CLI flags before parsing the actual command line.
- **Resultset overrides** – The location of the `.resultset.json` file can be specified via CLI options or in the MCP configuration. See [Configuring the Resultset](../index.md#configuring-the-resultset) for details.
- **Tracked globs** – Glob patterns (e.g., `lib/**/*.rb`) that specify which files should have coverage. When provided, cov-loupe alerts you if any matching files are missing from the coverage data, helping catch untested files that were added to the project but never executed during test runs.
- **Output character mode** – Global control of ASCII vs Unicode output via `-O/--output-chars` (CLI) or `output_chars` parameter (MCP). Default mode auto-detects terminal UTF-8 capability.
- **Colorized source** – CLI-only flags (`--source`, `--context-lines`, `--color`) enhance human-readable reports when working locally.

## Repository Layout Highlights

- `lib/cov_loupe/` – Core runtime (model, utilities, error handling, CLI, MCP server, tools).
- `lib/cov_loupe.rb` – Primary public entry point required by gem consumers.
- `lib/cov_loupe/paths/path_utils.rb` – Centralized path normalization and expansion logic.
- `docs/` – Audience-specific guides (`docs/user` for usage, `docs/dev` for contributors).
- `spec/` – RSpec suite with fixtures under `spec/fixtures/` for deterministic coverage data.

## Extending the System With a New Tool or Metric

1. Add or update data processing inside `CoverageModel` or `CoverageCalculator` when a new metric is needed.
2. Surface that metric through all interfaces: add a CLI option/subcommand, create an MCP tool, and expose a library helper method.
3. Register the new tool in `MCPServer` and update CLI option parsing in `CoverageCLI`.
4. Provide tests under `spec/` mirroring the lib path (`spec/cov_loupe/..._spec.rb`).
5. Update documentation to reflect the new capability.

By funnelling every interface through the shared `CoverageModel`, cov-loupe guarantees that CLI users, MCP clients, and embedding libraries all observe identical coverage semantics and staleness rules, while still allowing each adapter to tailor presentation and error handling to its audience.
