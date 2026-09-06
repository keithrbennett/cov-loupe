<!-- Invisible SEO-friendly H1 -->
<h1 style="position:absolute; left:-9999px; top:auto; width:1px; height:1px; overflow:hidden;">
  CovLoupe
</h1>

<p style="text-align:center; margin-bottom:-36px;">
  <img src="https://raw.githubusercontent.com/keithrbennett/cov-loupe/main/dev/images/cov-loupe-logo.png" alt="CovLoupe logo" width="560">
</p>

<p style="text-align:center;">
  An MCP server, command line utility, and library for Ruby SimpleCov test coverage analysis.
</p>

<p style="text-align:center;">
  <strong><a href="https://keithrbennett.github.io/cov-loupe/">Documentation Website</a></strong>
</p>

[![Gem Version](https://badge.fury.io/rb/cov-loupe.svg)](https://badge.fury.io/rb/cov-loupe)
[![Documentation](https://img.shields.io/badge/docs-online-blue.svg)](https://keithrbennett.github.io/cov-loupe/)

## What is cov-loupe?

**cov-loupe** makes SimpleCov coverage data queryable and actionable through three interfaces:

- **CLI** - command-line execution of single reports or queries
- **MCP server** - stdio (localhost nonnetwork) server assists AI analysis of your coverage
- **Ruby library** - Programmatic API for custom tooling

Works with SimpleCov's `coverage.json` (the documented JSON formatter output, written alongside the HTML report from SimpleCov 1.0.0 on) and with `.resultset.json` (SimpleCov's internal merge cache, used by SimpleCov 0.21 and 0.22)—no runtime dependency on your test suite.

### Key Features

- ✅ **Multiple interfaces** - CLI, MCP server, and Ruby API
- **Annotated source code** - `-s full|uncovered|none` / `--source full|uncovered|none` with `-c N` / `--context-lines N` for context lines
- ✅ **Staleness detection** - Identify outdated coverage (missing files, timestamp mismatches, line count changes)
- ✅ **Multi-suite support** - Automatic merging of multiple test suites (RSpec + Cucumber, etc.)
- ✅ **Flexible path resolution** - Works with absolute or relative paths
- ✅ **Comprehensive error handling** - Context-aware messages for each mode

### Practical Use Cases

- Query coverage data from AI assistants, e.g.:
  - "Using cov-loupe, analyze test coverage data and write a report to a markdown file containing a free text analysis of each issue and then two tables, one sorted in descending order of urgency, the other in ascending order of level of effort."
  - "Using cov-loupe, generate a table of directories and their average coverage rates, in ascending order of coverage."
- Find files with the lowest coverage
- Investigate specific files or directories
- Generate CI/CD coverage reports
- Create custom pass/fail predicates for scripts and CI - use the library API or CLI JSON output to implement arbitrarily complex coverage rules beyond simple thresholds (e.g., require higher coverage for critical paths, exempt test utilities, track coverage trends)

## Quick Start

### Installation

```sh
gem install cov-loupe

# Or, for the most current version you may need to specify prerelease:
gem install --pre cov-loupe
```

### Upgrading

If you are upgrading from a previous version, please refer to the [Migration Guides](docs/user/migrations/README.md).

### Generate Coverage Data

```sh
# Generate your SimpleCov test coverage data with your test suite run command, e.g.:
bundle exec rspec

# Verify coverage was generated
ls -l coverage/coverage.json    # SimpleCov 1.0.0 and later
ls -l coverage/.resultset.json  # SimpleCov 0.21 and 0.22
```

### Basic Usage

**CLI - View Coverage Table:** This is the default command, so any of the following will work:
```sh
cov-loupe
cov-loupe l
cov-loupe list
```

**CLI - Check Specific File:**
```sh
cov-loupe summary lib/cov_loupe/model/model.rb
# or use abbreviations: s (summary), u (uncovered)
cov-loupe s lib/cov_loupe/model/model.rb
cov-loupe u lib/cov_loupe/cli.rb
```

**CLI - Find Project Resources:**

The repo URL, doc server URL, and local gem filespec are output in the header of the online help, e.g.:

```
Repository:            https://github.com/keithrbennett/cov-loupe
Documentation (Web):   https://keithrbennett.github.io/cov-loupe/
Documentation (Local): /Users/kbennett/.local/share/mise/installs/ruby/4.0.5/lib/ruby/gems/4.0.0/gems/cov-loupe-VERSION/README.md
```

There is a p/--path-for option that will get an individual value for each of these:

```
cov-loupe -p repo
cov-loupe -p docs
cov-loupe -p docs-local
```

You can use your operating system's application open command (usually `open` for Mac, `xdg-open` on Linux, and `start` on Windows) to assemble this into a single command:

```
open `cov-loupe -p docs`
```

**Ruby Library:**
```ruby
require "cov_loupe"

model = CovLoupe::CoverageModel.new
list_result = model.list
files = list_result["files"]
# => [{ "file" => "/path/to/project/lib/cov_loupe/model/model.rb", "covered" => 114, "total" => 118, "percentage" => 96.61, "stale" => "ok" }, ...]

summary = model.summary_for("lib/cov_loupe/model/model.rb")
# => { "file" => "/path/to/project/lib/cov_loupe/model/model.rb", "summary" => { "covered" => 114, "total" => 118, "percentage" => 96.61 } }
```

Use `model.relativize(...)` when you want library payloads with project-relative paths. See [Library API](docs/user/LIBRARY_API.md) for details.

**MCP Server:**
See [MCP Integration Guide](docs/user/MCP_INTEGRATION.md) for AI assistant setup.

**Important for MCP users:** MCP servers must keep `stdout` clean until the protocol handshake begins. If `cov-loupe -m mcp` prints text such as `Resolving dependencies...` before responding, see [Troubleshooting](docs/user/TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup) and [MCP Integration](docs/user/MCP_INTEGRATION.md#stdout-must-stay-clean-during-mcp-startup) for wrapper and RubyGems launcher guidance.

## Multi-Suite Coverage

Projects with multiple test suites (RSpec + Cucumber, etc.) are automatically merged. See [Multi-Suite Coverage Merging](docs/user/ADVANCED_USAGE.md#multi-suite-coverage-merging) for details and current limitations.

## Documentation Index

Full documentation is available at **[https://keithrbennett.github.io/cov-loupe/](https://keithrbennett.github.io/cov-loupe/)**.

**User Guides:**

- [Quick Start](docs/QUICKSTART.md) - Get up and running in 3 steps
- [User Docs Overview](docs/user/README.md) - Map of all end-user guides
- [Installation](docs/user/INSTALLATION.md) - Setup for different environments
- [CLI Usage](docs/user/CLI_USAGE.md) - Command-line reference
- [Examples](docs/user/EXAMPLES.md) - Common use cases
- [Advanced Usage](docs/user/ADVANCED_USAGE.md) - Staleness detection, error modes, path resolution
- [Library API](docs/user/LIBRARY_API.md) - Ruby API documentation
- [Error Handling](docs/user/ERROR_HANDLING.md) - Error modes and exceptions
- [MCP Integration](docs/user/MCP_INTEGRATION.md) - AI assistant configuration
- [Troubleshooting](docs/user/TROUBLESHOOTING.md) - Common issues

**Special Topics & Prompts:**

- [CLI Fallback for LLMs](docs/user/CLI_FALLBACK_FOR_LLMS.md) - When MCP isn't available
- [Sample MCP Prompts](docs/user/prompts/README.md) - Ready-to-use ChatGPT/Claude/Gemini prompts
- [Migration Guides](docs/user/migrations/README.md)
  - [Migrate to v6](docs/user/migrations/MIGRATING_TO_V6.md)
  - [Migrate to v5](docs/user/migrations/MIGRATING_TO_V5.md)
  - [Migrate to v4](docs/user/migrations/MIGRATING_TO_V4.md)
  - [Migrate to v3](docs/user/migrations/MIGRATING_TO_V3.md)
  - [Migrate to v2](docs/user/migrations/MIGRATING_TO_V2.md)

**Developer Docs:**

- [Developer Docs Overview](docs/dev/README.md) - Entry point for contributors
- [Architecture](docs/dev/ARCHITECTURE.md) - Design and internals
- [Development Guide](docs/dev/DEVELOPMENT.md) - Local dev workflow
- [Releasing](docs/dev/RELEASING.md) - Release checklist
- [Future Enhancements](docs/dev/FUTURE_ENHANCEMENTS.md) - Planned improvements
- [Architecture Decision Records](docs/dev/arch-decisions/README.md) - Design history

**Project Docs & Examples:**

- [Contributing](docs/contributing.md)
- [Code of Conduct](docs/code_of_conduct.md)
- [Release Notes](docs/release_notes.md)
- [License](docs/license.md)
- [MCP Input Examples](docs/examples/mcp-inputs.md)
- [Predicate Examples](docs/examples/success_predicates.md)

## Requirements

- **Ruby >= 3.2** (required by `mcp` gem dependency)
- `mcp` gem >= 0.15 and < 2.0
- SimpleCov-generated `coverage.json` or `.resultset.json` file
- `simplecov` gem >= 0.21

Applications pinned to an older `mcp` version must upgrade it before installing cov-loupe v6.

### JRuby Compatibility

The test suite passes on JRuby, and to the best of our knowledge the project is fully JRuby-compatible.
If you encounter any JRuby-specific issues, please open a GitHub issue, including as much detail as possible.

## Configuring the Coverage File

`cov-loupe` reads either of SimpleCov's two on-disk formats:

- **`coverage.json`** — the documented output of SimpleCov's JSON formatter, described by a versioned JSON schema. From SimpleCov 1.0.0 on, the default HTML formatter writes it alongside its report.
- **`.resultset.json`** — SimpleCov's internal merge cache, keyed by test suite. This is the only format available in SimpleCov 0.21 and 0.22.

The format is detected from the file's contents, not its name, so an explicitly supplied path of either format is read correctly whatever it is called.

**Discovery precedence.** With no `--coverage-file` argument, the search is *format-first*: every default `coverage.json` location is checked before any `.resultset.json` location, and the first file found wins.

1. `coverage.json`
2. `coverage/coverage.json`
3. `tmp/coverage.json`
4. `.resultset.json`
5. `coverage/.resultset.json`
6. `tmp/.resultset.json`

When `--coverage-file` names a **directory**, `coverage.json` inside it is preferred over `.resultset.json`. When it names a **file**, that file is used as given.

Because `coverage.json` wins over `.resultset.json` regardless of location or age, a stale `coverage.json` left over from an earlier run will be chosen ahead of a freshly written `.resultset.json`. Pass `--coverage-file` with an explicit path to select a specific file.

For non-standard locations:

```sh
# Command-line option (highest priority) - use -r or --coverage-file
cov-loupe -r /path/to/your/coverage

# Environment variable (project-wide default)
export COV_LOUPE_OPTS="-r /path/to/your/coverage"

# MCP server configuration
# Add to your MCP client config (used as defaults for MCP tools):
# "args": ["-r", "/path/to/your/coverage"]
```

### Deprecated `resultset` names

Before `coverage.json` support, the input was always a `.resultset.json`, and the API said so. Every name below still works and now emits a one-time deprecation warning; all of them are removed in **v7.0.0**.

| Deprecated | Use instead |
| --- | --- |
| `--resultset PATH` | `--coverage-file PATH` (`-r` is unchanged) |
| `resultset` MCP tool argument | `coverage_file` |
| `CoverageModel.new(resultset:)` | `CoverageModel.new(coverage_file:)` |
| `CoverageModel#resultset_path` | `#coverage_file_path` |
| `CoverageReporter.report(resultset:)` | `report(coverage_file:)` |
| `CovLoupe::ResultsetNotFoundError` | `CovLoupe::CoverageFileNotFoundError` |
| `Resolvers::ResultsetPathResolver` | `Resolvers::CoverageFilePathResolver` |
| `AppConfig#resultset` | `#coverage_file` |

The warning goes to stderr (and the log) in CLI and library mode, and to the log only in MCP mode, where stderr is server noise. `CovLoupe::Deprecation.enabled = false` silences it.

`ResultsetLoader` keeps its name: it reads `.resultset.json` specifically, so the name is accurate.

**MCP precedence:** For MCP tool calls, per-request JSON parameters win over the CLI args used to start the server (including `COV_LOUPE_OPTS`). If neither is provided, built-in defaults are used (`root: '.'`, `raise_on_stale: false`, etc.). Coverage data is cached globally and automatically reloaded when the coverage file changes.

See [CLI Usage Guide](docs/user/CLI_USAGE.md) for complete details.



## Common Workflows

### Find Coverage Gaps

```sh
# Files with worst coverage
cov-loupe -o d list           # -o = --sort-order, d = descending (worst at end)
cov-loupe list | less         # display table in pager, best files first (worst at end)
cov-loupe list | head -10     # truncate the table

# Filter to specific patterns (see COV_LOUPE_OPTS best practice below)
cov-loupe -g "lib/cov_loupe/tools/**/*.rb" list  # -g = --tracked-globs

# Export for analysis
cov-loupe -fJ list > coverage-report.json
```

### Best Practice: Match SimpleCov Configuration

For accurate coverage tracking and validation, set `COV_LOUPE_OPTS` to match your SimpleCov `track_files` patterns. See [`--tracked-globs`](docs/user/CLI_USAGE.md#tracked-globs) for the canonical setup example and default behavior.

### Working with JSON Output

The `-fJ` flag enables programmatic processing of coverage data using command-line JSON tools.

**Using jq:**
```sh
# Filter files below 80% coverage
cov-loupe -fJ list | jq '.files[] | select(.percentage < 80)'
```

**Using Ruby one-liners:**
```sh
# Count files below threshold
cov-loupe -fJ list | ruby -r json -e '
  puts JSON.parse($stdin.read)["files"].count { |f| f["percentage"] < 80 }
'
```

**Using rexe:**

[rexe](https://github.com/keithrbennett/rexe) is a Ruby gem that enables shorter Ruby command lines by providing command-line options for input and output formats, plus other conveniences. It eliminates the need for explicit JSON parsing and formatting code.

Install: `gem install rexe`

```sh
# Filter files below 80% coverage with pretty-printed JSON output
cov-loupe -fJ list | rexe -ij -mb -oJ 'self["files"].select { |f| f["percentage"] < 80 }'

# Count files below threshold
cov-loupe -fJ list | rexe -ij -mb -op 'self["files"].count { |f| f["percentage"] < 80 }'

# Human-readable output with AmazingPrint
cov-loupe -fJ list | rexe -ij -mb -oa 'self["files"].first(3)'
```

With rexe's `-ij -mb` options, `self` automatically becomes the parsed JSON object. The same holds true for JSON output -- using `-oJ` produces pretty-printed JSON without explicit formatting calls. Rexe also supports YAML input/output (`-iy`, `-oy`) and AmazingPrint output (`-oa`) for human consumption.

### When Coverage Rows Are Skipped

If a coverage row has corrupt or malformed data, the CLI now logs and *warns* after rendering the report.
This lets operators immediately see that totals may be incomplete. Example table output:

```text
$ cov-loupe list
┌─────────────────────────────┬──────────┬─────────┬───────┬───────┐
│ File                        │        % │ Covered │ Total │ Stale │
├─────────────────────────────┼──────────┼─────────┼───────┼───────┤
│ lib/foo.rb                  │   66.67% │       2 │     3 │       │
│ lib/bar.rb                  │   33.33% │       1 │     3 │       │
└─────────────────────────────┴──────────┴─────────┴───────┴───────┘
Files: total 2, ok 2, stale 0

WARNING: 1 coverage row skipped due to errors:
  - lib/corrupt.rb: Invalid coverage line array: contains non-integer elements: ["bad"]
Run again with --raise-on-stale to exit when rows are skipped.
```

Multi-line, indented JSON (`-fJ`) reports still emit valid JSON to `stdout`; the warning continues to be printed on `stderr`:

```text
$ cov-loupe -fJ list
{
  "files": [
    { "file": "lib/foo.rb", "covered": 2, "total": 3, "percentage": 66.67, "stale": "ok" },
    { "file": "lib/bar.rb", "covered": 1, "total": 3, "percentage": 33.33, "stale": "ok" }
  ],
  "skipped_files": [
    {
      "file": "lib/corrupt.rb",
      "error": "Invalid coverage line array: contains non-integer elements: [\"bad\"]",
      "error_class": "CovLoupe::CoverageDataError"
    }
  ],
  "missing_tracked_files": [],
  "newer_files": [],
  "deleted_files": [],
  "length_mismatch_files": [],
  "unreadable_files": [],
  "timestamp_status": "ok",
  "counts": { "total": 2, "ok": 2, "stale": 0 }
}

WARNING: 1 coverage row skipped due to errors:
  - lib/corrupt.rb: Invalid coverage line array: contains non-integer elements: ["bad"]
Run again with --raise-on-stale to exit when rows are skipped.
```

Use `--raise-on-stale true` (or `-S true`) to turn these warnings into hard failures for CI pipelines.

Run `rexe -h` to see all available options, or visit the [rexe project page](https://github.com/keithrbennett/rexe) for more examples.

For comprehensive JSON processing examples, see [user/EXAMPLES.md](docs/user/EXAMPLES.md).

### CI/CD Integration

```sh
# Fail build if coverage is stale (--raise-on-stale or -S)
cov-loupe --raise-on-stale true list || exit 1

# Generate coverage report artifact
cov-loupe -fJ list > artifacts/coverage.json
```

### Investigate Specific Files

```sh
# Quick summary
cov-loupe summary lib/cov_loupe/model/model.rb

# See uncovered lines
cov-loupe uncovered lib/cov_loupe/cli.rb

# View in context
cov-loupe -s u -c 3 uncovered lib/cov_loupe/cli.rb  # -s = --source (u = uncovered, n = none to disable), -c = --context-lines

# Detailed hit counts
cov-loupe detailed lib/cov_loupe/coverage/coverage_calculator.rb

# Project totals
cov-loupe totals
cov-loupe -fJ totals
```

### Boolean CLI Options

Boolean flags such as `--color` (short: `-C`) and `--raise-on-stale` (short: `-S`) require explicit boolean arguments. Recognized literals:

|        |        |
|--------|--------|
| `yes`  | `no`   |
| `y`    | `n`    |
| `true` | `false`|
| `t`    | `f`    |
| `on`   | `off`  |
| `+`    | `-`    |
| `1`    | `0`    |

Each row lists the equivalent `true` token (left) and `false` token (right).

```sh
cov-loupe --color false        # disable ANSI colors explicitly
cov-loupe -C false             # short form
cov-loupe --raise-on-stale yes # enforce stale coverage failures
```

## Commands and Tools

**CLI Subcommands:** `list (l)`, `summary (s)`, `uncovered (u)`, `detailed (d)`, `raw (r)`, `totals (t)`, `validate (v)`

**MCP Tools:** `file_coverage_summary`, `file_coverage_detailed`, `file_coverage_raw`, `file_uncovered_lines`, `project_coverage`, `project_coverage_totals`, `project_validate`, `help`, `version`

📖 **See also:**
- [CLI Usage Guide](docs/user/CLI_USAGE.md) - Complete command-line reference
- [MCP Integration Guide](docs/user/MCP_INTEGRATION.md#available-mcp-tools-functions) - MCP tools documentation

## Troubleshooting

- **"command not found"** - See [Installation Guide](docs/user/INSTALLATION.md#require-path)
- **"cannot load such file -- mcp"** - Requires Ruby >= 3.2. Verify: `ruby -v`
- **"Could not find coverage.json or .resultset.json"** - Ensure SimpleCov is configured in your test suite, then run tests to generate coverage. See the [Configuring the Coverage File](#configuring-the-coverage-file) section for more details.
- **MCP server won't connect** - Check PATH and Ruby version in [MCP Troubleshooting](docs/user/MCP_INTEGRATION.md#troubleshooting)
- **RVM in sandboxed environments (macOS)** - RVM requires `/bin/ps` which may be blocked by sandbox restrictions. Use rbenv or chruby instead.

For more detailed help, see the full [Troubleshooting Guide](docs/user/TROUBLESHOOTING.md).

## Development

```sh
# Clone and setup
git clone https://github.com/keithrbennett/cov-loupe.git
cd cov-loupe
bundle install

# Run tests
bundle exec rspec

# Test locally
bundle exec exe/cov-loupe

# Build and install
gem build cov-loupe.gemspec
gem install cov-loupe-*.gem
```

See [dev/DEVELOPMENT.md](docs/dev/DEVELOPMENT.md) for more.

## SimpleCov Dependency

`cov-loupe` declares a runtime dependency on `simplecov` (>= 0.21) to support multi-suite merging using SimpleCov's combine helpers. The dependency is lazy-loaded only when needed, ensuring fast startup for single-suite projects.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass (`bundle exec rspec`)
5. Submit a pull request

## License

MIT License - see [LICENSE](docs/license.md) file for details.

## Links

- **GitHub:** https://github.com/keithrbennett/cov-loupe
- **RubyGems:** https://rubygems.org/gems/cov-loupe
- **Issues:** https://github.com/keithrbennett/cov-loupe/issues
- **Changelog:** [RELEASE_NOTES.md](docs/release_notes.md)

---

## Next Steps

📦 **Install:** `gem install cov-loupe`

📖 **Read:** [CLI Usage Guide](docs/user/CLI_USAGE.md) | [MCP Integration](docs/user/MCP_INTEGRATION.md)

🐛 **Report issues:** [GitHub Issues](https://github.com/keithrbennett/cov-loupe/issues)

⭐ **Star the repo** if you find it useful!
