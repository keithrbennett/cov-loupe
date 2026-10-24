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

**[Documentation Website](https://keithrbennett.github.io/cov-loupe/)**

[![Gem Version](https://badge.fury.io/rb/cov-loupe.svg)](https://badge.fury.io/rb/cov-loupe)
[![Documentation](https://img.shields.io/badge/docs-online-blue.svg)](https://keithrbennett.github.io/cov-loupe/)

## What is cov-loupe?

**cov-loupe** makes SimpleCov coverage data queryable and actionable through three interfaces:

- **CLI** - command-line execution of single reports or queries
- **MCP server** - stdio (local, no network) server assists AI analysis of your coverage
- **Ruby library** - Programmatic API for custom tooling

Reads SimpleCov's `coverage.json`, the documented JSON formatter output that SimpleCov 1.0.0 and later write alongside the HTML report—no runtime dependency on your test suite.

### Key Features

- ✅ **Multiple interfaces** - CLI, MCP server, and Ruby API
- ✅ **Annotated source code** - `-s full|uncovered|none` / `--source full|uncovered|none` with `-n N` / `--context-lines N` for context lines around uncovered code
- ✅ **Staleness detection** - Identify outdated coverage (deleted, newer, line count mismatched, or unreadable files)
- ✅ **Multi-suite aware** - Reads SimpleCov's already-merged `coverage.json`, so RSpec + Cucumber (etc.) appear as one coverage map
- ✅ **Flexible path resolution** - Works with absolute or relative paths
- ✅ **Comprehensive error handling** - Context-aware messages for each mode

### Practical Use Cases

- Query coverage data from AI assistants, e.g.:
  - "Using the cov-loupe MCP server, analyze test coverage data and write a report to a markdown file containing a free text analysis of each issue and then two tables, one sorted in descending order of urgency, the other in ascending order of level of effort."
  - "Using the cov-loupe MCP server, generate a table of directories and their average coverage rates, in ascending order of coverage."
  - For prompts that explain what your tests miss and why it matters, see [AI Assistant Prompts](docs/user/examples/ai-assistant-prompts.md).
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

If your project doesn't use SimpleCov yet, add it to your `Gemfile` and install it:

```sh
bundle add simplecov --group test --require false
```

Then start it at the very top of `spec/spec_helper.rb` (or `test/test_helper.rb`), before your application code loads:

```ruby
require 'simplecov'
SimpleCov.start
```

Then run your test suite:

```sh
# Generate your SimpleCov test coverage data with your test suite run command, e.g.:
bundle exec rspec

# Verify coverage was generated
ls -l coverage/coverage.json
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
cov-loupe summary lib/my_app/order.rb
# or use abbreviations: s (summary), u (uncovered)
cov-loupe s lib/my_app/order.rb
cov-loupe u lib/my_app/cli.rb
```

**CLI - Find Project Resources:**

The repo URL, documentation site URL, and path to the installed README are output in the header of the online help, e.g. (excerpt):

```
Repository:            https://github.com/keithrbennett/cov-loupe
Documentation (Web):   https://keithrbennett.github.io/cov-loupe/
Documentation (Local): /path/to/gems/cov-loupe-VERSION/README.md
Screencast:            https://www.bbs-software.com/screencasts/cov-loupe
```

The `-p`/`--path-for` option prints the repository and documentation paths individually:

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
# => { "schema_version" => 1, "files" => [...], ... }
files = list_result["files"]
# => [{ "file" => "lib/my_app/order.rb", "covered" => 114, "total" => 118, "percentage" => 96.61, "stale" => "ok" }, ...]

summary = model.summary_for("lib/my_app/order.rb")
# => { "schema_version" => 1, "file" => "lib/my_app/order.rb", "summary" => { "covered" => 114, "total" => 118, "percentage" => 96.61 } }
```

Library payloads report file paths relative to the project root, like the CLI and MCP output; files outside the root keep absolute paths. See [Library API](docs/user/LIBRARY_API.md#schema-version) for the payload compatibility rules.

Only the public API defined under [Public API and Versioning](docs/user/LIBRARY_API.md#public-api-and-versioning), including Ruby classes and methods tagged `@api public`, follows Semantic Versioning; other classes and methods in the gem are internal and may change in any release.

**MCP Server:**
See [MCP Integration Guide](docs/user/MCP_INTEGRATION.md) for AI assistant setup.

**Important for MCP users:** An MCP server's `stdout` carries only protocol messages, from startup until it exits. If `cov-loupe -m mcp` prints text such as `Resolving dependencies...` before responding, see [Troubleshooting](docs/user/TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup) and [MCP Integration](docs/user/MCP_INTEGRATION.md#stdout-must-stay-clean) for wrapper and RubyGems launcher guidance.

## Multi-Suite Coverage

SimpleCov merges the results of the suites that ran (RSpec + Cucumber, etc.) before writing `coverage.json`, dropping results older than its merge timeout (10 minutes by default), so cov-loupe sees one combined coverage map and does no merging of its own. `coverage.json` has one timestamp for the merged result, so if only some suites were re-run after a change, staleness may be under-reported. To combine coverage from separate CI jobs, keep each job's `coverage/.resultset.json` and merge them with `SimpleCov.collate` (for example, `SimpleCov.collate Dir['coverage-*/.resultset.json']`), which writes a combined `coverage.json`; `SimpleCov.collate` reads `.resultset.json` files, not `coverage.json`.

## Documentation Index

Full documentation is available at **[https://keithrbennett.github.io/cov-loupe/](https://keithrbennett.github.io/cov-loupe/)**.

**User Guides:**

- [Quick Start](docs/QUICKSTART.md) - Get up and running in 3 steps
- [User Docs Overview](docs/user/README.md) - Map of all end-user guides
- [Installation](docs/user/INSTALLATION.md) - Setup for different environments
- [CLI Usage](docs/user/CLI_USAGE.md) - Command-line reference
- [Examples](docs/user/EXAMPLES.md) - AI assistant prompts, CLI and Ruby recipes, CI/CD integration
- [Advanced Usage](docs/user/ADVANCED_USAGE.md) - Staleness detection, error modes, path resolution
- [Library API](docs/user/LIBRARY_API.md) - Ruby API documentation
- [Error Handling](docs/user/ERROR_HANDLING.md) - Error modes and exceptions
- [Logging](docs/user/LOGGING.md) - Log targets, initialization probes, and file creation
- [MCP Integration](docs/user/MCP_INTEGRATION.md) - AI assistant configuration
- [Troubleshooting](docs/user/TROUBLESHOOTING.md) - Common issues

**Special Topics & Prompts:**

- [CLI Fallback for LLMs](docs/user/CLI_FALLBACK_FOR_LLMS.md) - When MCP isn't available
- [Sample MCP Prompts](docs/user/prompts/README.md) - Ready-to-use ChatGPT/Claude/Gemini prompts
- [Migration Guides](docs/user/migrations/README.md)
  - [Migrate to v7](docs/user/migrations/MIGRATING_TO_V7.md)
  - [Migrate to v6](docs/user/migrations/MIGRATING_TO_V6.md)
  - [Migrate to v5](docs/user/migrations/MIGRATING_TO_V5.md)
  - [Migrate to v4](docs/user/migrations/MIGRATING_TO_V4.md)
  - [Migrate to v3](docs/user/migrations/MIGRATING_TO_V3.md)
  - [Migrate to v2](docs/user/migrations/MIGRATING_TO_V2.md)

**Developer Docs:**

- [Developer Docs Overview](docs/dev/README.md) - Entry point for contributors
- [Architecture](docs/dev/ARCHITECTURE.md) - Design and internals
- [Development Guide](docs/dev/DEVELOPMENT.md) - Local dev workflow
- [Documentation Server](docs/dev/DOC_SERVER.md) - Local docs server and publishing
- [Releasing](docs/dev/RELEASING.md) - Release checklist
- [Future Enhancements](docs/dev/FUTURE_ENHANCEMENTS.md) - Planned improvements
- [Architecture Decision Records](docs/dev/arch-decisions/README.md) - Design history

**Project Docs & Examples:**

- [Contributing](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Release Notes](RELEASE_NOTES.md)
- [License](LICENSE)
- [MCP Input Examples](examples/mcp-inputs/README.md)
- [Predicate Examples](examples/success_predicates/README.md)

## Requirements

- **Ruby >= 3.3** (the oldest Ruby that has not reached end of life)
- `mcp` gem >= 0.15 and < 2.0
- A `coverage.json` written by SimpleCov 1.x (SimpleCov itself is not a cov-loupe dependency)

`gem install` installs `mcp` and the other runtime dependencies (`amazing_print` and `logger`) automatically.

Applications pinned to an `mcp` version older than 0.15 must upgrade it (required since cov-loupe v6), and projects on SimpleCov 0.x must upgrade SimpleCov to produce the `coverage.json` cov-loupe v7 reads. See [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md).

### JRuby Compatibility

The test suite passes on JRuby, and to the best of our knowledge the project is JRuby-compatible, except that non-ASCII paths under `LANG=C` are unsupported because the JVM cannot open them in that locale.
If you encounter any JRuby-specific issues, please open a GitHub issue, including as much detail as possible.

## Configuring the Coverage File

`cov-loupe` reads `coverage.json`, the output of SimpleCov's JSON formatter. It is described by a versioned JSON schema in the SimpleCov repository, and from SimpleCov 1.0.0 on the default HTML formatter writes it alongside its report, so most projects have one after every test run.

SimpleCov's `.resultset.json` is not read. It is SimpleCov's internal merge cache with no compatibility promises. cov-loupe 6.x and earlier read only that file; 7.0 replaced it with `coverage.json`.

**Discovery.** With no `--coverage-file` argument, `coverage/coverage.json` under the project root is used. That is where SimpleCov writes it by default; for any other location, pass `--coverage-file` (`-c`).

When `--coverage-file` names a **directory**, `coverage.json` inside it is used. When it names a **file**, that file is used as given. A relative path is tried against both the current directory and the project root; if both resolve to different existing locations, it is an ambiguity error, so use an absolute path.

For non-standard locations:

```sh
# Command-line option (highest priority) - use -c or --coverage-file
cov-loupe -c /path/to/your/coverage

# Environment variable (project-wide default)
export COV_LOUPE_OPTS="-c /path/to/your/coverage"

# MCP server configuration
# Add to your MCP client config (used as defaults for MCP tools):
# "args": ["-m", "mcp", "-c", "/path/to/your/coverage"]
```

**MCP precedence:** For MCP tool calls, per-request JSON parameters win over the CLI args used to start the server (including `COV_LOUPE_OPTS`). If neither is provided, built-in defaults are used (`root: '.'`, `raise_on_stale: false`, etc.). Coverage data is cached globally and automatically reloaded when the coverage file changes.

See [CLI Usage Guide](docs/user/CLI_USAGE.md) for complete details.



## Commands and Tools

**CLI Subcommands:** `list (l)`, `summary (s)`, `uncovered (u)`, `detailed (d)`, `raw (r)`, `totals (t)`, `validate (v)`

**MCP Tools:** `file_coverage_summary`, `file_coverage_detailed`, `file_coverage_raw`, `file_uncovered_lines`, `project_coverage`, `project_coverage_totals`, `project_validate` (only when the server is started with `--allow-code-predicates`), `help`, `version`

📖 **See also:**

- [CLI Usage Guide](docs/user/CLI_USAGE.md) - Complete command-line reference
- [MCP Integration Guide](docs/user/MCP_INTEGRATION.md#available-mcp-tools-functions) - MCP tools documentation

## Troubleshooting

- **"command not found"** - See [Installation Guide](docs/user/INSTALLATION.md#require-path)
- **"cannot load such file -- mcp"** - The `mcp` gem is not installed for the Ruby you are running. Reinstall cov-loupe (`gem install cov-loupe`) or run `bundle install`.
- **"Could not find coverage.json"** - Ensure SimpleCov is configured in your test suite, then run tests to generate coverage. See the [Configuring the Coverage File](#configuring-the-coverage-file) section for more details.
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

## SimpleCov Compatibility

`cov-loupe` does not depend on the `simplecov` gem and never loads it. It reads `coverage.json` written by SimpleCov 1.x, which is already merged across suites. On load it checks the file's `meta.schema_version` (SimpleCov's output format version, e.g. `"1.0"`) and rejects a missing value or a major version other than 1 with an error naming the file and the value found. That includes `coverage.json` files written for SimpleCov 0.x by the separate `simplecov_json_formatter` gem, which carry no `schema_version`.

## Contributing

Contributions are welcome! Please open an issue first and wait for explicit approval before submitting a pull request. Then:

1. Fork the repository and create a feature branch
2. Add tests for new functionality
3. Ensure RuboCop and the tests pass (`bundle exec rubocop` and `bundle exec rspec`)
4. Submit a pull request

See the [Contributing Guide](CONTRIBUTING.md) for details.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Links

- **GitHub:** https://github.com/keithrbennett/cov-loupe
- **RubyGems:** https://rubygems.org/gems/cov-loupe
- **Issues:** https://github.com/keithrbennett/cov-loupe/issues
- **Changelog:** [RELEASE_NOTES.md](RELEASE_NOTES.md)

---

## Next Steps

📦 **Install:** `gem install cov-loupe`

📖 **Read:** [CLI Usage Guide](docs/user/CLI_USAGE.md) | [MCP Integration](docs/user/MCP_INTEGRATION.md)

🐛 **Report issues:** [GitHub Issues](https://github.com/keithrbennett/cov-loupe/issues)

⭐ **Star the repo** if you find it useful!
