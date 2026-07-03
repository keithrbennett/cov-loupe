# Release Notes

[Back to main README](docs/index.md)


## v6.0.0.pre (Breaking)

- **Stdout logging is no longer permitted.** The `--log-file` / `-l` option no longer accepts `stdout` in any mode (CLI, MCP, or library). Logs are diagnostics and must not corrupt command output on `stdout` or the MCP JSON-RPC protocol stream.
    - **Old:** `--log-file stdout` was allowed in CLI mode and rejected only in MCP mode.
    - **New:** `--log-file stdout` raises a `ConfigurationError` during normal configuration validation. Use `--log-file stderr`, a file path, or `:off` to disable logging.
    - See [Migrating to v6](docs/user/migrations/MIGRATING_TO_V6.md) for details.
- **`--format` short codes and long names normalized.** Each format now has exactly one canonical short code and one canonical long name; noncanonical aliases (`pretty-json`, `awesome_print`, `ap`) are no longer accepted. New formats `inspect`, `puts`, and `pretty_print` were added.
    - **Old:** `p`/`pretty_json`/`pretty-json` meant multi-line, indented JSON. `a`/`amazing_print`/`awesome_print`/`ap` meant AmazingPrint. `J` was unassigned.
    - **New:** `p` means `puts` (Ruby `Kernel#puts` output). `J` means `pretty_json` (multi-line, indented JSON). `P` means `pretty_print` (Ruby stdlib `PP.pp` output). `i` means `inspect` (Ruby `#inspect` output). `a`/`amazing_print` is unchanged; `awesome_print`/`ap` are no longer accepted.
    - Canonical formats: `a`/`amazing_print`, `i`/`inspect`, `j`/`json`, `J`/`pretty_json`, `p`/`puts`, `P`/`pretty_print`, `t`/`table`, `y`/`yaml`.
    - See [Migrating to v6](docs/user/migrations/MIGRATING_TO_V6.md) for details.

## v5.0.1.pre
- Extract shared RuboCop defaults into `.rubocop-shared.yml` and slim `.rubocop.yml` down to cov-loupe-specific overrides, making lint configuration easier to maintain across related projects.
- Align the codebase and spec suite with the updated RuboCop rules, including removal of the project-specific line-length override and the corresponding style-only cleanup in Ruby sources and tests.
- Expand `AGENTS.md` with Ruby-specific contributor guidance: inspect core project config files before editing, prefer `bundle exec` and binstubs, and run the smallest relevant test first.

## v5.0.0 (Breaking)
- **MCP tool names renamed** to encode scope: file-scope tools are prefixed with `file_` (`file_coverage_summary`, `file_coverage_detailed`, `file_coverage_raw`, `file_uncovered_lines`); project-scope tools are prefixed with `project_` (`project_coverage_list`, `project_coverage_totals`, `project_coverage_table`, `project_validate`). `help_tool` and `version_tool` drop the `_tool` suffix and become `help` and `version`.

- **Removed `version` subcommand**: `cov-loupe version` no longer exists. Use `cov-loupe -v` or `cov-loupe --version` instead.
- **Simplified `--version` output**: `-v`/`--version` now prints only the bare version string (e.g. `5.0.0`) and exits, instead of displaying a formatted table with `Gem Root` and `Documentation` fields. JSON format is no longer supported for version output.
- Add `-s none` / `--source none` option to disable source code display (previously enabled via `-s full` or `-s uncovered`).
- Add canonical resource retrieval via CLI: `cov-loupe --path-for[=NAME]` (`-p[NAME]`).
  - Standardize canonical resource keys across CLI and MCP to `repo`, `docs`, and `docs-local`.
  - Expose canonical resources in MCP `help` under the `resources` key (alongside `tools`).
  - Share resource values from one source of truth (`CovLoupe::Resources::RESOURCE_MAP`) used by:
      - CLI `--path-for`
      - CLI help banner URLs
      - MCP `help`
      - MCP server startup instructions
- **Single-letter abbreviations for CLI subcommands**: All CLI subcommands can now be abbreviated to their first letter. For example, `cov-loupe l` for `list`, `cov-loupe s` for `summary`, `cov-loupe r` for `raw`, `cov-loupe u` for `uncovered`, `cov-loupe d` for `detailed`, `cov-loupe t` for `totals`, `cov-loupe v` for `validate`.
- **Coverage key renamed**: The `percent_covered` key in coverage summary hashes (returned by `file_coverage_summary`, `project_coverage`, `project_coverage_totals`, and related CLI/MCP outputs) has been renamed to `percentage`. Update any code or scripts that read `percent_covered` to use `percentage` instead.
- Make pass/fail symbols in source code display more prominent, change circle to X
- Fix `validate -i` parsing in the top-level argument parser so inline validate code is handled correctly.

## v4.0.0 (Breaking)

- **Removed Branch Coverage Support**: Removed logic that synthesized line coverage from branch-only coverage data. This feature was complex and rarely used. Users should use standard line coverage configuration in SimpleCov.
    - Removed `docs/dev/BRANCH_ONLY_COVERAGE.md`.
- **⚠️ MCP mode now requires `-m/--mode mcp` flag**: Automatic mode detection has been removed. MCP users **must** update their MCP server configuration to include `-m mcp` or `--mode mcp` or the server will run in CLI mode and hang. See migration guide for setup commands.
    - **Old**: Mode was auto-detected based on TTY/stdin status, with optional `--force-mode cli|mcp|auto` override
    - **New**: Mode defaults to `cli`. Use `-m mcp` or `--mode mcp` to run as MCP server. No auto-detection.
    - **Rationale**: Auto-detection caused issues with piped input, CI environments, and CLI-only flags (e.g., `cov-loupe --format json` would hang in MCP mode)
- **Unified stale coverage enforcement**: New `--raise-on-stale` / `raise_on_stale` boolean replaces the old `--staleness`/`check_stale` combo across CLI, Ruby, and MCP interfaces. When true, `cov-loupe` raises if any file or the project totals are stale; when false, staleness is reported but execution continues.
- **Ruby API method renamed**: `CoverageModel#all_files_coverage` renamed to `CoverageModel#list` for consistency with CLI subcommand naming.
- **Ruby API return type changed**: `CoverageModel#list` now returns a **hash** with comprehensive staleness information instead of just an array of files. The hash includes keys: `files` (array), `skipped_files`, `missing_tracked_files`, `newer_files`, and `deleted_files`. Update code to use `model.list['files']` when you need just the file array.
- **Ruby API signature change**: `CovLoupe::Resolvers::CoverageLineResolver` now requires `root:` (no default), and `ResolverHelpers.lookup_lines` / `create_coverage_resolver` require `root:` as well.
- **Dependency update**: Replaced unmaintained `awesome_print` with `amazing_print` (`~> 2.0`).
    - CLI: `--format amazing_print` is now the preferred way to specify the pretty-print formatter. `-f ap` and `--format awesome_print` are still supported.
    - Library: `require 'awesome_print'` is replaced by `require 'amazing_print'`.
    - Library: Internal format symbol changed from `:awesome_print` to `:amazing_print`.
        - `CovLoupe::AppConfig#format` now returns `:amazing_print` when configured for that output.
        - `CovLoupe::Formatters.format(obj, :amazing_print)` is the new API method.
- **Internal Logger API changed**: `CovLoupe::Logger.new` now requires `mode:` (symbol) instead of `mcp_mode:` (boolean).
    - Use `CovLoupe::Logger.new(target: t, mode: :cli|:mcp|:library)` instead of `mcp_mode: true/false`.
- **Deleted files now raise `FileNotFoundError`**: Previously, querying a file that was deleted after coverage was generated would incorrectly return stale coverage data. This was misleading for metrics and violated the documented API contract. Now properly raises `FileNotFoundError` for missing files, regardless of whether coverage data exists in the resultset.
    - **Old**: `model.summary_for('deleted_file.rb')` would return coverage data with exit 0
    - **New**: `model.summary_for('deleted_file.rb')` raises `CovLoupe::FileNotFoundError`
    - **Rationale**: Deleted files represent stale data that pollutes metrics. The API documentation already promised `FileNotFoundError` for missing files; the implementation now matches the contract.
- **Staleness check errors now return `"error"` marker**: Previously, when staleness checking itself failed (e.g., file permission errors, resolver failures, unexpected exceptions), the `stale` field returned `false`, making errors indistinguishable from fresh files. Now returns `"error"` to explicitly indicate a failed staleness check.
    - **Old**: `{ "file": "...", "stale": false }` (error silently treated as fresh)
    - **New**: `{ "file": "...", "stale": "error" }` (error explicitly flagged)
    - **Impact**: Code checking `stale == false` or using truthiness checks (`if payload['stale']`) will need updating. Error is still logged for debugging.
    - **Frequency**: Rare - only affects error conditions during staleness checking (not normal staleness detection)
- **Path resolution now handles case-sensitivity and path separators correctly (NEW in v4.0.0)**: Path normalization now independently handles two concerns: (1) slash normalization for Windows backslashes, and (2) case-folding for case-insensitive volumes. Case-sensitivity is detected lazily on first use by testing the project root volume (prefers using existing files via `File.identical?` to avoid writes; falls back to temporary file creation if needed).
    - **Windows**: Paths are now case-insensitive with backslash normalization (`C:\Foo\Bar.rb` matches `c:/foo/bar.rb`)
    - **macOS**: Most macOS users have case-insensitive APFS volumes - path lookups like `lib/Foo.rb` will now correctly match `lib/foo.rb` in coverage data. This may surface previously-hidden case mismatches in test code.
    - **Linux**: Typically case-sensitive (no change in behavior for most users)
    - **Special cases**: Correctly handles case-sensitive APFS volumes (macOS formatted with `-s`) and external drives
    - **Limitation**: All coverage files are assumed to be on the same volume as the project root. Mixed-volume coverage data (e.g., files from both case-sensitive and case-insensitive volumes) is not supported.
    - **Why**: A filesystem type (APFS, ext4, NTFS) can have multiple volumes with different case-sensitivity settings. Platform assumptions are insufficient. Runtime detection is the only accurate approach.
- **Stricter staleness detection for line count mismatches**: Removed the trailing newline adjustment heuristic that could mask legitimate code additions (false negatives). Previously, if a file's line count was exactly one more than the coverage data and the file was missing a trailing newline, the staleness checker would adjust the count and report the file as fresh. This heuristic was risky because it couldn't distinguish between a harmless missing newline and a developer adding a line of code while simultaneously removing the trailing newline. All line count mismatches are now treated as significant staleness indicators.
    - **Old**: File with 101 lines (no trailing newline) matching 100 coverage lines → reported as fresh (adjusted)
    - **New**: File with 101 lines matching 100 coverage lines → reported as stale (length mismatch)
    - **Impact**: More conservative staleness detection may flag some files that were previously considered fresh. This is intentional to prevent false negatives.
    - **Rationale**: Prioritizes accuracy over convenience. Better to flag a file as stale and re-run tests than to miss actual code changes.
- **⚠️ `--tracked-globs` default changed to empty array**: The `--tracked-globs` CLI option now defaults to `[]` (empty) instead of `lib/**/*.rb,app/**/*.rb,src/**/*.rb`. The Ruby API also changed from `nil` to `[]` for consistency (both behave identically, so no functional change). This prevents silently excluding coverage results that don't match assumed project patterns and avoids false positives when detecting missing files.
    - **Old**: CLI defaulted to `lib/**/*.rb,app/**/*.rb,src/**/*.rb` - files outside these patterns were excluded from output
    - **New**: CLI and Ruby API default to `[]` (empty) - shows all files in the resultset without filtering
    - **Affects**: CLI (`cov-loupe list`) and Ruby API signature (`CoverageModel.new` - behavior unchanged, only default parameter value changed for consistency)
    - **Impact**: CLI users who relied on automatic filtering or missing-file detection will need to explicitly set `--tracked-globs`
    - **Migration (CLI)**: Set `COV_LOUPE_OPTS="--tracked-globs lib/**/*.rb,app/**/*.rb"` in your shell config to match your SimpleCov `track_files` patterns
    - **Migration (Ruby API)**: No action needed - behavior unchanged (nil and [] both normalize to empty array)
    - **Rationale**:
        - **Transparency**: Shows all coverage data without hiding files that don't match assumptions
        - **No false positives**: Broad patterns flag migrations, bin scripts, etc. as "missing"
        - **Project variety**: Different projects use different structures (lib/, app/, src/, config/, etc.)
    - **Important**: Files lacking any coverage at all (not loaded during tests) will not appear in the resultset and therefore won't be visible with the default empty array. To detect such files, you must set `--tracked-globs`

### ✨ Enhancements

- **New `-f p` shortcut for pretty-json format**: Added `-f p` as a shortcut for `--format pretty-json`. This follows the pattern of other format shortcuts (`-f j` for json, `-f y` for yaml, etc.). The previous `-f J` shortcut no longer works (use `-f p` instead).

- **Project totals now include coverage breakdowns**: The `totals` subcommand and `project_coverage_totals` now return explicit `with_coverage` and `without_coverage` breakdowns, plus tracking metadata, so totals clearly separate fresh coverage from missing coverage.

  **Example output:**
  ```json
  {
    "lines": { "total": 100, "covered": 90, "uncovered": 10, "percent_covered": 90.0 },
    "tracking": { "enabled": true, "globs": ["lib/**/*.rb"] },
    "files": {
      "total": 10,
      "with_coverage": {
        "total": 9,
        "ok": 8,
        "stale": {
          "total": 1,
          "by_type": {
            "missing_from_disk": 0,
            "newer": 1,
            "length_mismatch": 0,
            "unreadable": 0
          }
        }
      },
      "without_coverage": {
        "total": 1,
        "by_type": {
          "missing_from_coverage": 1,
          "unreadable": 0,
          "skipped": 0
        }
      }
    }
  }
  ```

  Table format also includes a file breakdown section after totals.

  **Breaking change:** The JSON shape for totals has changed (the old `percentage` and `excluded_files` fields are removed).

**📖 For complete migration guide, see [docs/user/migrations/MIGRATING_TO_V4.md](docs/user/migrations/MIGRATING_TO_V4.md)**

## v3.0.0

### 🚨 BREAKING CHANGE: GEM RENAMED simplecov-mcp → cov-loupe

This is a **major version bump** because the gem has been completely renamed from **simplecov-mcp** to **cov-loupe**. This requires manual intervention to migrate.

#### What Changed
- **Gem name**: `simplecov-mcp` → `cov-loupe`
- **Executable**: `simplecov-mcp` → `cov-loupe`
- **Repository**: `github.com/keithrbennett/simplecov-mcp` → `github.com/keithrbennett/cov-loupe`
- **Module name**: `SimpleCovMcp` → `CovLoupe`
- **Require path**: `require 'simplecov_mcp'` → `require 'cov_loupe'`
- **Environment variable**: `SIMPLECOV_MCP_OPTS` → `COV_LOUPE_OPTS`
- **Log file**: `simplecov_mcp.log` → `cov_loupe.log`
- **Documentation alias**: `smcp` → `clp`

#### What Stayed the Same
- **All functionality**: No breaking changes to features or APIs

#### Migration Steps
1. Uninstall old gem: `gem uninstall simplecov-mcp`
2. Install new gem: `gem install cov-loupe`
3. Update scripts/aliases: Change `simplecov-mcp` to `cov-loupe`
4. Update Ruby code: Rename `SimpleCovMcp` to `CovLoupe` and update requires.
5. Update env vars: Rename `SIMPLECOV_MCP_OPTS` to `COV_LOUPE_OPTS`

**📖 For complete migration guide, see [docs/user/migrations/MIGRATING_TO_V3.md](docs/user/migrations/MIGRATING_TO_V3.md)**

**Note**: The old `simplecov-mcp` gem (v2.0.1) will remain available on RubyGems but will not receive further updates.

### ✨ Other Changes
- Add logo and avatar images, display in readme

## v2.0.1

- Improve help text
- Add a prompt


## v2.0.0

### 🚨 BREAKING CHANGES

Version 2.0 introduces several breaking changes to improve consistency and align with Ruby conventions. Key changes include:

- **CLI**: Global options must now precede subcommands (e.g., `simplecov-mcp --format json list` instead of `simplecov-mcp list --format json`)
- **Options renamed**: `--stale` → `--staleness`, `--source-context` → `--context-lines`, `--json` → `--format`
- **Error modes**: `on` → `log`, `trace` → `debug`
- **Subcommands**: `--success-predicate` flag replaced with `validate` subcommand
- **Source option**: Now requires explicit mode (`--source full` or `--source uncovered`)
- **Default sort**: Changed from ascending to descending (best coverage first)
- **MCP tools**: Parameter `stale` renamed to `staleness`, error modes updated
- **Ruby API**: `CLIConfig` renamed to `AppConfig`, field changes (`json` → `format`, `stale_mode` → `staleness`)

**📖 For complete migration guide with examples, see [docs/user/migrations/MIGRATING_TO_V2.md](docs/user/migrations/MIGRATING_TO_V2.md)**

### ✨ New Features

- **validate subcommand**: File mode (`validate <file>`) and inline mode (`validate -i <code>`)
- **MCP support**: New `project_validate` with `code` and `file` parameters

---

## v1.1.0

- Add a `totals` CLI subcommand and matching `project_coverage_totals` that report covered/total/uncovered line counts plus the average coverage percent.
- Refactor command line and environment argument handling

## v1.0.1 (2025-10-23)

- Make error output more helpful when a result set file is not found, esp. when the command name is run without args in a non-project directory.

## v1.0.0 (2025-10-18)

🎉 **Major Release: Production-Ready Coverage Analysis Tool**

This release represents a complete maturation of simplecov-mcp from experimental proof-of-concept to production-ready tool. The v1.0.0 milestone brings comprehensive documentation, robust error handling, extensive test coverage, architectural improvements, and a polished user experience across all three interfaces (MCP server, CLI, and Ruby library).

### 🌟 Major Features

#### Multi-Suite Coverage Merging
- **Automatic merging** of multiple test suites from a single `.resultset.json` file (e.g., RSpec + Cucumber)
- **Lazy loading** of SimpleCov dependency - only loaded when multi-suite merging is needed
- **Performance optimized** - single-suite projects remain fast with no SimpleCov runtime overhead
- See `docs/user/ADVANCED_USAGE.md` for configuration details

#### Branch Coverage Support (with Limitations)
- **Branch-level data handling** - reads and processes SimpleCov branch coverage data
- **Line-level aggregation** - branch hits are summed per line since individual branch tracking isn't supported yet
- **Graceful degradation** - use native SimpleCov HTML reports for detailed branch-by-branch analysis
- See `docs/dev/BRANCH_ONLY_COVERAGE.md` for details and limitations

#### Enhanced Staleness Detection
- **Three staleness indicators**:
    - `M` - File modified after coverage run (timestamp-based)
    - `T` - File timestamp unavailable or coverage missing
    - `L` - Line count mismatch between source and coverage
- **Per-file reporting** in all outputs (CLI tables, JSON, MCP responses)
- **Configurable modes**: `--stale off|error` for CI/CD integration
- Improved edge case handling for files outside project root

#### Success Predicates for CI/CD
- **Custom exit code logic** via `--success-predicate` flag
- **Ruby code evaluation** - Load lambdas or other callable objects to define coverage policies
- **Flexible policy definitions** - Check minimum thresholds, file-based rules, directory-specific requirements, etc.
- **Examples provided** in `examples/success_predicates/`:
    - Project-wide minimum coverage
    - Per-directory thresholds
    - Class-based policies
    - Maximum low-coverage file count
- See `docs/user/ADVANCED_USAGE.md#success-predicates` for usage and security considerations

#### Comprehensive CLI Enhancements
- **Default command improved** - `simplecov-mcp` shows sorted coverage table (no subcommand needed)
- **Flexible sorting** - `--sort-order a|d` or `--sort-order ascending|descending`
- **Annotated source code** - `--source=full|uncovered` with `--source-context N` for context lines
- **Optional colorization** - `-C/--color [BOOLEAN]` for source code output
- **Tracked globs** - `--tracked-globs PATTERN` to filter files or detect new untested files
- **User-specified defaults via environment variable** - `SIMPLECOV_MCP_OPTS` environment variable value is prepended to ARGV for option parsing
- **Configurable logging** - `--log-file PATH` or `stdout`/`stderr` (default: `./simplecov_mcp.log`)

### 🏗️ Architecture & Code Quality

#### Major Refactoring
- **Command pattern** - CLI subcommands extracted to individual command classes (`lib/simplecov_mcp/commands/`)
- **Presenter pattern** - Shared presentation logic for all output formats (`lib/simplecov_mcp/presenters/`)
- **Resolver pattern** - Path and coverage line resolution extracted to dedicated classes (`lib/simplecov_mcp/resolvers/`)
- **Factory pattern** - Error handlers and command instantiation centralized
- **Shared test examples** - DRY test suite with shared behaviors documented in `spec/shared_examples/README.md`

#### Error Handling Overhaul
- **Context-aware errors** - Different error strategies for CLI, library, and MCP server modes
- **Three error modes**: `off`, `log`, `debug` (configurable via `--error-mode` or `SIMPLECOV_MCP_OPTS`)
- **Custom exception hierarchy** - `SimpleCovMcp::Error` base class with specific subtypes
- **Logging fallback** - Graceful degradation to stderr when log file is unavailable (CLI/library modes only)
- **Structured MCP errors** - JSON-RPC compliant error responses with proper error codes
- See `docs/user/ERROR_HANDLING.md` for complete reference

#### Improved Path Resolution
- **Multi-strategy matching**:
  1. Exact absolute path
  2. Path without working directory prefix
  3. Basename (filename) fallback
- **New `PathRelativizer` class** - Consistent relative path handling across codebase
- **Configurable root** - `--root PATH` option to resolve relative paths against different directories

#### Test Coverage Excellence
- **Comprehensive test suite** - 546 examples across 55 test files
- **High coverage** - 98.49% line coverage, 90.36% branch coverage (self-reported via SimpleCov)
- **Integration tests** - Real-world scenarios in `spec/integration_spec.rb`
- **MCP integration tests** - JSON-RPC protocol validation in `spec/mcp_server_integration_spec.rb`
- **Edge case testing** - Exhaustive error condition coverage in `spec/errors_edge_cases_spec.rb`
- **Test documentation** - `spec/MCP_INTEGRATION_TESTS_README.md` and `spec/TIMESTAMPS.md`

### 📚 Documentation Overhaul

#### Comprehensive Documentation Suite
All documentation moved under audience-specific directories (`docs/user` for usage guides, `docs/dev` for contributor content):

**Getting Started:**
- `docs/user/INSTALLATION.md` - Installation for all environments (gem, Bundler, source, RVM, rbenv, etc.)
- `docs/user/CLI_USAGE.md` - Complete command-line reference with examples
- `docs/user/EXAMPLES.md` - Common use cases and workflows

**Advanced Usage:**
- `docs/user/ADVANCED_USAGE.md` - Success predicates, multi-suite merging, resultset configuration
- `docs/user/MCP_INTEGRATION.md` - AI assistant setup (Claude Code, Cursor, Zed, etc.)
- `docs/user/LIBRARY_API.md` - Complete Ruby API documentation with recipes

**Reference:**
- `docs/user/ERROR_HANDLING.md` - Error modes, exception types, logging
- `docs/user/TROUBLESHOOTING.md` - Common issues and solutions
- `docs/dev/ARCHITECTURE.md` - System design and component overview
- `docs/dev/DEVELOPMENT.md` - Contributing guide
- `docs/dev/BRANCH_ONLY_COVERAGE.md` - Branch coverage support and limitations

**Architectural Decisions:**
- `docs/dev/arch-decisions/*.md` - 5 detailed ADRs documenting major design decisions
- `docs/dev/arch-decisions/README.md` - Index and overview

**Additional Resources:**
- `docs/dev/presentations/simplecov-mcp-presentation.md` - Slide deck for talks/demos
- `examples/success_predicates/README.md` - Success predicate examples and patterns
- `prompts/*.md` - AI prompt templates for coverage analysis

#### Improved README
- **Value proposition first** - Clear explanation of what simplecov-mcp does and why it matters
- **Quick Start section** - Get running in 3 steps
- **Audience-based organization** - Documentation grouped by user journey (Getting Started, Advanced, Reference)
- **Next Steps section** - Clear calls-to-action at end
- **Reduced length** - Main README streamlined from 967 lines to 272 lines by extracting content to dedicated docs

### 🔧 Developer Experience

#### Configuration Improvements
- **Environment variable options** - `SIMPLECOV_MCP_OPTS` prepended to ARGV for option parsing
- **Force CLI mode** - `--force-cli` flag to disable MCP server mode detection
- **Flexible resultset location** - Multiple resolution strategies with sensible defaults
- **Normalized options** - Consistent internal representation of enumerated options (symbols)

#### Logging Enhancements
- **Configurable log file** - `--log-file PATH` (or `-l`) command-line option
- **Programmatic control** - `SimpleCovMcp.default_log_file=` and `SimpleCovMcp.active_log_file=` for runtime changes
- **Mode-aware logging** - MCP mode prohibits `stdout` logging (would corrupt JSON-RPC protocol), allows `stderr` or file
- **Timestamped log entries** - All log messages include ISO 8601 timestamps

#### Build & Release
- **Dependabot integration** - Automated dependency updates (`.github/dependabot.yml`)
- **License added** - MIT License (`LICENSE` file)
- **Gemspec improvements** - Tighter version constraints, correct file list
- **Version command** - `simplecov-mcp version` for easy version checking

### 🐛 Bug Fixes

#### CLI Fixes
- **Subcommand extraction** - Fixed `--source` flag incorrectly treated as subcommand (see the subcommand list in `lib/simplecov_mcp/constants.rb`)
- **Option argument parsing** - Centralized list of options expecting arguments to prevent similar bugs
- **Invalid option handling** - Clean error messages for unrecognized CLI flags
- **Help text formatting** - Improved readability and consistency

#### Path Resolution Fixes
- **Double-path bug** - Fixed resultset resolver creating invalid paths like `spec/fixtures/project1/spec/fixtures/project1/coverage`
- **Relative path handling** - Stopped indiscriminately running `File.absolute_path(resultset, @root)` on already-absolute paths
- **Files outside root** - Graceful handling of coverage data for files outside project root directory

#### Coverage Processing Fixes
- **Branch-only coverage** - No longer crashes on resultsets with branch data but no line data
- **String timestamps** - Handles both integer and string timestamps in resultset JSON
- **Multiple resultsets** - Proper merging when `.resultset.json` contains multiple test suite entries
- **Line count mismatches** - Accurate staleness detection handles trailing newline differences between source and coverage data

#### Error Handling Fixes
- **Library mode exceptions** - Consistent `SimpleCovMcp::Error` exceptions (not bare `RuntimeError`)
- **MCP error format** - JSON-RPC compliant error responses
- **Missing resultset** - Clear error messages with actionable suggestions
- **Fallback logging** - stderr logging when primary log destination is unavailable (not in MCP mode)

### 🔄 Breaking Changes

#### Naming Consistency
- **Module name** - Now consistently `SimpleCovMcp` (matching SimpleCov's single-word style)
- **Legacy shim removed** - `SimpleCov::Mcp` entry point no longer supported
- **Require path** - Changed from `simple_cov/mcp` to `simplecov_mcp`
- **File paths** - All files moved from `lib/simple_cov_mcp/` to `lib/simplecov_mcp/`

#### Option Changes
- **Removed environment variables**: `SIMPLECOV_RESULTSET`, `SIMPLECOV_MCP_CLI`, `SIMPLECOV_MCP_DEBUG`, `SIMPLECOV_MCP_LOG`
- **New environment variable**: `SIMPLECOV_MCP_OPTS` - use this instead (supports all CLI options including `--log-file`)
- **CLI flag removed**: `--cli` (replaced by `--force-cli`)
- **Error mode enum**: Changed from `--debug` to `--error-mode trace|on|off`
- **Subcommand changes**: `table` and `all-files` subcommands merged into `list`

#### API Changes
- **CoverageModel constructor** - Options now use consistent symbol keys (not mixed strings/symbols)
- **Staleness return values** - Changed from boolean to letter codes (`'M'`, `'T'`, `'L'`, or `false`)
- **Error classes** - Custom exception hierarchy replaces generic `RuntimeError`

### 📊 Statistics

- **175 files changed** with 15,712 insertions and 2,142 deletions
- **152 commits** since v0.3.0
- **Comprehensive documentation** - 12 major documentation files in `docs/`, 5 ADRs, 7 example scripts
- **Test coverage** - Self-reported coverage via SimpleCov (view with `simplecov-mcp list`)

### 🙏 Acknowledgments

This release benefited from extensive AI pair programming sessions with Codex, Claude Code, GLM-4.6 (Z-AI), Gemini, and Warp.

See `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` for AI agent integration notes.

### 📦 Upgrade Guide

#### From v0.3.0

1. **Update require statements:**
   ```ruby
   # Old
   require 'simple_cov/mcp'

   # New
   require 'simplecov_mcp'
   ```

2. **Update environment variables:**
   ```sh
   # Old
   export SIMPLECOV_RESULTSET=/path/to/coverage
   export SIMPLECOV_MCP_DEBUG=1

   # New
   export SIMPLECOV_MCP_OPTS="--resultset /path/to/coverage --error-mode trace"
   ```

3. **Update CLI commands:**
   ```sh
   # Old
   simplecov-mcp table
   simplecov-mcp all-files

   # New (merged into 'list')
   simplecov-mcp list
   simplecov-mcp        # default command is 'list'
   ```

4. **Update MCP configurations:**
   - Review `docs/user/MCP_INTEGRATION.md` for updated setup instructions
   - Log file now defaults to `./simplecov_mcp.log` (was `~/simplecov_mcp.log`)

5. **Handle new error types in library code:**
   ```ruby
   # Old
   rescue RuntimeError => e

   # New
   rescue SimpleCovMcp::FileError => e
   rescue SimpleCovMcp::ConfigurationError => e
   rescue SimpleCovMcp::Error => e  # catch-all
   ```

### 🔮 Possible Future Improvements

- **Per-file staleness timestamps** in multi-suite scenarios
- **Multiple resultset file merging** (currently only merges suites within single file)
- **Full branch coverage support** with individual branch tracking
- **Web interface** for interactive coverage exploration
- **Additional output formats** (HTML reports, badges, etc.)

### 🔗 Links

- **Changelog:** [RELEASE_NOTES.md](docs/release_notes.md)
- **GitHub:** https://github.com/keithrbennett/simplecov-mcp
- **RubyGems:** https://rubygems.org/gems/simplecov-mcp
- **Issues:** https://github.com/keithrbennett/simplecov-mcp/issues

---

**Full Changelog**: v0.3.0...v1.0.0

---

## v0.2.1

* Fixed JSON data key issue and resulting test failure.

## v0.2.0

* Massive enhancements and improvements.

## v0.1.0

* Initial version.
