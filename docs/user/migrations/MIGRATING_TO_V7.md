# Migrating to v7.0

[Back to Migration Guides](README.md)

This document describes the breaking changes introduced in version 7.0.0.

## Table of Contents

- [Only `coverage.json` Is Read; SimpleCov 1.0 Is Required](#only-coveragejson-is-read-simplecov-10-is-required)
- [`resultset` Names Removed from the CLI, MCP Tools, and Library API](#resultset-names-removed-from-the-cli-mcp-tools-and-library-api)
- [Short Options `-c` and `-n` Reassigned](#short-options--c-and--n-reassigned)
- [Only `coverage/coverage.json` Is Searched by Default](#only-coveragecoveragejson-is-searched-by-default)

---

## Only `coverage.json` Is Read; SimpleCov 1.0 Is Required {#only-coveragejson-is-read-simplecov-10-is-required}

cov-loupe now reads a single input: `coverage.json`, the output of SimpleCov's JSON formatter. SimpleCov 1.0.0 and later write it alongside the HTML report by default, and its shape is fixed by a versioned JSON schema in the SimpleCov repository.

`.resultset.json`, SimpleCov's internal merge cache, is no longer read. cov-loupe's `simplecov` dependency is now `>= 1.0, < 2.0` (previously `>= 0.21`), so `bundle install` fails for projects pinned to SimpleCov 0.x.

**Rationale:**

- `.resultset.json` is an undocumented internal file with no compatibility promises; `coverage.json` is the interface SimpleCov documents for downstream tools.
- Reading `coverage.json` instead of `.resultset.json` removes the runtime SimpleCov load (needed to merge multi-suite resultsets) and the code that adapted to `.resultset.json`'s historical shape variations. Supporting *both* would have added a second loader and a format-precedence rule to document, so v7 switches outright.

**Before (v6.x):**

```sh
# .resultset.json was found automatically (also tried: ./.resultset.json, tmp/.resultset.json)
ls coverage/.resultset.json
cov-loupe list
cov-loupe --resultset coverage/.resultset.json list      # explicit resultset
```

**After (v7.0):**

```sh
# Only coverage.json is found; it is written by SimpleCov 1.0+ after every test run
ls coverage/coverage.json
cov-loupe list
cov-loupe --coverage-file coverage/coverage.json list     # explicit file
cov-loupe --coverage-file coverage list                   # directory containing coverage.json
```

**Migration:**

- Upgrade SimpleCov to 1.0 or later in the project whose coverage you inspect, then re-run the test suite so `coverage/coverage.json` exists. If your project uses a custom formatter list, make sure it includes `SimpleCov::Formatter::HTMLFormatter` or `SimpleCov::Formatter::JSONFormatter`, either of which writes `coverage.json`.
- Replace any `--resultset` / `-r` argument (on the command line, in `COV_LOUPE_OPTS`, or in MCP server `args`) with `--coverage-file` / `-c`, and any `resultset:` keyword with `coverage_file:`, naming `coverage.json` or the directory containing it. See the next section for the full list of renames.
- If you cannot upgrade SimpleCov, stay on cov-loupe 6.x, which reads `.resultset.json`.

**Error message change:** the not-found message is now `Could not find coverage.json under "<root>"; run tests or set --coverage-file option`, and a directory argument without one raises `No coverage.json found in directory: <dir>`. Scripts matching the old `Could not find .resultset.json under "<root>"; run tests or set --resultset option` text must be updated.

**Staleness output change:** the file line in stale-coverage errors now reads `Coverage file - <path>` instead of `Resultset - <path>`.

## `resultset` Names Removed from the CLI, MCP Tools, and Library API {#resultset-names-removed-from-the-cli-mcp-tools-and-library-api}

v7.0 replaces every `resultset` name in the CLI, MCP tools, and library API with a `coverage_file` name. This is a single clean break: the old names are removed outright, with no deprecation period and no aliases.

| Removed | Use instead |
| --- | --- |
| `--resultset PATH` | `--coverage-file PATH` (short form `-c`; see below) |
| `resultset` MCP tool argument | `coverage_file` |
| `CoverageModel.new(resultset:)` | `CoverageModel.new(coverage_file:)` |
| `CoverageModel#resultset_path` | `#coverage_file_path` |
| `CoverageReporter.report(resultset:)` | `report(coverage_file:)` |
| `CovLoupe::ResultsetNotFoundError` | `CovLoupe::CoverageFileNotFoundError` |
| `CoverageDataStaleError#resultset_path`, `CoverageDataProjectStaleError#resultset_path` | `#coverage_file_path` |
| `Resolvers::ResultsetPathResolver` | `Resolvers::CoverageFilePathResolver` |
| `ResolverHelpers.find_resultset` | `.find_coverage_file` |
| `ResolverHelpers.create_resultset_resolver` (and its `candidates:` keyword) | `Resolvers::CoverageFilePathResolver.new(root:)` |
| `AppConfig#resultset`, `#resultset=` | `#coverage_file`, `#coverage_file=` |
| `CovLoupe::ResultsetLoader` | `CovLoupe::CoverageJsonLoader` |

**Before (v6.x):**

```sh
cov-loupe --resultset coverage list      # worked
```

```ruby
model = CovLoupe::CoverageModel.new(resultset: 'coverage')
rescue CovLoupe::ResultsetNotFoundError
```

**After (v7.0):**

```sh
cov-loupe --coverage-file coverage list  # or: cov-loupe -c coverage list
```

```ruby
model = CovLoupe::CoverageModel.new(coverage_file: 'coverage')
rescue CovLoupe::CoverageFileNotFoundError
```

**Migration:**

- Replace every name in the left column with the one on the right. `--resultset` on the command line (including in `COV_LOUPE_OPTS` and MCP server `args`) now fails as an unknown option; the `resultset` MCP tool argument is rejected as an unexpected argument.
- `CoverageJsonLoader.load(resolved_coverage_file:)` returns a `Result` with `coverage_map` and `timestamp` only. The `suite_names` member of the old `ResultsetLoader::Result` is gone, since `coverage.json` is a single merged result.

## Short Options `-c` and `-n` Reassigned {#short-options--c-and--n-reassigned}

The coverage file option, `-r`/`--resultset` in 6.x, is `-c`/`--coverage-file` in 7.0. `-c` previously belonged to `--context-lines`, whose short form is now `-n`. The `--context-lines` long form is unchanged.

| Option | 6.x | 7.0 |
| --- | --- | --- |
| Coverage file | `-r`, `--resultset PATH` | `-c`, `--coverage-file PATH` |
| Context lines | `-c`, `--context-lines N` | `-n`, `--context-lines N` |

**Before (v6.x):**

```sh
cov-loupe -r build/coverage list
cov-loupe -s u -c 3 uncovered lib/foo.rb
export COV_LOUPE_OPTS="-r build/coverage"
```

**After (v7.0):**

```sh
cov-loupe -c build/coverage list
cov-loupe -s u -n 3 uncovered lib/foo.rb
export COV_LOUPE_OPTS="-c build/coverage"
```

**Migration:**

- Replace `-r` with `-c` (and `--resultset` with `--coverage-file`) wherever it names the coverage file: command lines, shell aliases, `COV_LOUPE_OPTS`, and MCP server `args`. `-r` now fails with `ambiguous option: -r` (it is a prefix of the long options `--root` and `--raise-on-stale`).
- Replace `-c N` with `-n N` wherever it sets context lines. This is the one silent change: an old `-c 3` is now parsed as `--coverage-file 3` and fails with `Specified coverage file not found` rather than an unknown-option error.
- The not-found tip in CLI mode now reads `Specify a coverage file: cov-loupe -c PATH`.

## Only `coverage/coverage.json` Is Searched by Default {#only-coveragecoveragejson-is-searched-by-default}

With no `--coverage-file` argument, cov-loupe now looks in exactly one place: `coverage/coverage.json` under the project root, which is where SimpleCov writes it by default. 6.x searched three locations for `.resultset.json`: the project root itself, `coverage/`, and `tmp/`.

**Rationale:** the extra locations were guesses rather than anything SimpleCov produces, and a list of fallbacks has to be documented and reasoned about. A single conventional location plus an explicit option covers every real layout.

**Before (v6.x):**

```sh
# Any of these was found automatically
ls .resultset.json coverage/.resultset.json tmp/.resultset.json
cov-loupe list
```

**After (v7.0):**

```sh
# Only this one is found automatically
ls coverage/coverage.json
cov-loupe list

# Anything else needs the option (a file, or a directory containing coverage.json)
cov-loupe -c tmp list
cov-loupe -c ./coverage.json list
```

**Migration:** if your `coverage.json` lives anywhere other than `coverage/`, pass `--coverage-file` (`-c`) on the command line, set it in `COV_LOUPE_OPTS`, add it to your MCP server `args`, or pass `coverage_file:` to `CoverageModel.new`.

**Further reading:** [Configuring the Coverage File](../../index.md#configuring-the-coverage-file), [SimpleCov Integration](../../dev/arch-decisions/simplecov-integration.md), [Release Notes](../../release_notes.md).
