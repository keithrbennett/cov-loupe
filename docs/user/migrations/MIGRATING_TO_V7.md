# Migrating to v7.0

[Back to Migration Guides](README.md)

This document describes the breaking changes introduced in version 7.0.0.

## Table of Contents

- [Ruby 3.3 or Later Required](#ruby-33-or-later-required)
- [Structured Output Has a Schema Version](#structured-output-has-a-schema-version)
- [Only `coverage.json` Is Read; SimpleCov 1.x Output Is Required](#only-coveragejson-is-read-simplecov-10-is-required)
- [`resultset` Names Removed from the CLI, MCP Tools, and Library API](#resultset-names-removed-from-the-cli-mcp-tools-and-library-api)
- [Short Options `-c` and `-n` Reassigned](#short-options--c-and--n-reassigned)
- [Only `coverage/coverage.json` Is Searched by Default](#only-coveragecoveragejson-is-searched-by-default)
- [Logging Defaults, Target Probing, and Lazy File Creation](#logging-defaults-target-probing-and-lazy-file-creation)
- [CLI Exit Codes Remapped](#cli-exit-codes-remapped)
- [Percentages Truncated, Not Rounded](#percentages-truncated-not-rounded)
- [Staleness Values Renamed](#staleness-values-renamed)
- [Library Results Use Project-Relative Paths](#library-results-use-project-relative-paths)
- [`project_validate` Requires `--allow-code-predicates`](#project_validate-requires---allow-code-predicates)
- [Public API Declared](#public-api-declared)
- [`--output-chars ascii` No Longer Changes Data](#output-chars-ascii-no-longer-changes-data)

---

## Ruby 3.3 or Later Required {#ruby-33-or-later-required}

cov-loupe 7.0 requires Ruby 3.3 or later; 6.x supported Ruby 3.2, which has reached end of life. The gemspec's `required_ruby_version` is now `>= 3.3`, so Bundler and RubyGems will not install 7.0 on Ruby 3.2, and the `cov-loupe` executable exits with an error if run under an older Ruby (only `-v`/`--version` still works).

**Migration:** upgrade to Ruby 3.3 or later before upgrading cov-loupe, or stay on 6.x while you remain on Ruby 3.2.

## Structured Output Has a Schema Version {#structured-output-has-a-schema-version}

Every hash returned by a public `CoverageModel` coverage method, successful structured CLI payload (`-f json`, `pretty_json`, `yaml`, and the other non-table formats), and structured MCP tool payload now starts with top-level integer `"schema_version": 1`. The existing payload keys remain at the top level; there is no wrapper. For example, a file summary begins `{"schema_version":1,"file":"lib/foo.rb",...}`. MCP clients should check `result.isError` before parsing the tool content.

Library methods such as `CoverageModel#summary_for`, `#list`, and `#project_totals` now include this field, so saved JSON, YAML, or Marshal output carries the marker automatically. Table and text output, MCP `version` text, and error responses are unchanged. This version is separate from the gem version and from SimpleCov's `schema_version` in the input `coverage.json` file. See [Schema Version](../LIBRARY_API.md#schema-version) for the compatibility rules.

**Migration:** If a consumer compares exact top-level key sets or iterates every top-level key, account for `schema_version` before processing the coverage fields. Check that its value is `1` when reading saved payloads, and ignore other unknown keys.

## Logging Defaults, Target Probing, and Lazy File Creation {#logging-defaults-target-probing-and-lazy-file-creation}

v7 changes the default logging policy and validates explicit file-based logging
targets when a logger is initialized. CLI and MCP sessions now log to `stderr`
by default, while library contexts have logging disabled by default. Persistent
file logging requires an explicit target via `--log-file`,
`CovLoupe.default_log_file`, or `CovLoupe.active_log_file`.

The implicit `./cov_loupe.log` target and `COV-LOUPE-LOG-ERROR.log` fallback are
removed. Explicit file targets still have no built-in rotation, so users who
choose them are responsible for cleanup or external rotation.

For explicit file targets, v7 delays creating the persistent log file until the
first diagnostic is written. This prevents idle MCP servers from leaving empty
files behind while still detecting an invalid destination early.

Existing targets are checked in append mode. Missing targets are temporarily
created and removed during the probe, so a successful startup check does not
leave an empty file. Probe failures are cached and are not retried for every
message.

**Before (v6.x):** CLI and MCP sessions defaulted to `./cov_loupe.log`, and
logger construction eagerly created the configured log file, including when an
MCP server never emitted a diagnostic.

**After (v7.0):** CLI and MCP default to `stderr`; library contexts are quiet by
default; explicit file targets are probed during initialization and created only
on the first actual log write. Library mode raises `CovLoupe::LoggingError` for
an unusable explicit target; CLI mode reports a warning; and MCP mode returns
`isError: true` for a logging-target failure. Logging failures are secondary
diagnostics and do not replace the original MCP tool error.

The `stderr` target is also normalized consistently with `stdout` and `off`, so
case differences, surrounding whitespace, and symbol values such as `:stderr`
select the standard-error stream rather than a file path.

**Migration:**

- If you relied on the default `cov_loupe.log`, add an explicit `--log-file`
  path (or configure `CovLoupe.default_log_file` / `CovLoupe.active_log_file`).
  Otherwise, use the new `stderr` default or `off`.
- If you disabled logging with `--log-file :off` (or `-l :off`, including in
  `COV_LOUPE_OPTS` and MCP server configs), change it to `off`. `:off` is now treated as a
  file name. A log file literally named `off` must be written `./off`.
- The same applies in Ruby: change a `':off'` log target to `'off'` (or the symbol `:off`)
  wherever you pass one, for example `CovLoupe.default_log_file = ':off'`,
  `CovLoupe.active_log_file = ':off'`, a `log_target: ':off'` argument to `create_context`
  (v6 also required `error_handler:`), or `context.with(log_target: ':off')`. Left
  unchanged, they would write a log file named `:off` (or fail on Windows, where `:` is not
  allowed in file names).
- If you relied on `COV-LOUPE-LOG-ERROR.log` as an implicit emergency log,
  configure an explicit file target and arrange any desired external rotation.

## Only `coverage.json` Is Read; SimpleCov 1.x Output Is Required {#only-coveragejson-is-read-simplecov-10-is-required}

cov-loupe now reads a single input: `coverage.json`, the output of SimpleCov's JSON formatter. SimpleCov 1.0.0 and later write it alongside the HTML report by default, and its shape is fixed by a versioned JSON schema in the SimpleCov repository.

`.resultset.json`, SimpleCov's internal merge cache, is no longer read.

cov-loupe no longer depends on the `simplecov` gem (6.x declared `simplecov >= 0.21`), so installing cov-loupe neither installs SimpleCov nor constrains your project's SimpleCov version. Instead, each load checks `meta.schema_version` in `coverage.json` (SimpleCov's output format version, e.g. `"1.0"`). Any 1.x is accepted; a missing value or another major version fails with a message naming the file and the value found, for example:

```
Unsupported coverage.json format (meta.schema_version: nil) in /app/coverage/coverage.json; cov-loupe requires format 1.x (written by SimpleCov 1.0 and later)
```

When `meta.simplecov_version` is present, the message also includes it.

This also rejects `coverage.json` files written for SimpleCov 0.x by the separate `simplecov_json_formatter` gem, which have no `schema_version`. Upgrade SimpleCov to 1.x to produce a supported file.

**Rationale:**

- A load-time check of the file validates what cov-loupe actually reads; a gem dependency only constrained the SimpleCov installed alongside cov-loupe, which need not be the one that wrote the file, and forced SimpleCov into bundles that only inspect coverage.
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
| `CoverageRepository.new(coverage_file_path:)` | `CoverageRepository.new(coverage_file:)` |
| `CoverageRepository#coverage_file_path` | `#resolved_coverage_file` |

Of these, only the CLI option, the MCP argument, the `CoverageModel` names, `CoverageReporter.report(coverage_file:)`, and the error classes and readers are public in 7.0. The resolver, loader, repository, and `AppConfig` names are internal, so they may change again in any release; see [Public API Declared](#public-api-declared).

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
- `CoverageJsonLoader.load(path:)` and `CoverageJsonLoader.new(path:, logger:)` become `load(resolved_coverage_file:)` and `new(resolved_coverage_file:, logger:)`. They return a `Result` with `coverage_map` and `timestamp` only. The `suite_names` member of the old `ResultsetLoader::Result` is gone, since `coverage.json` is a single merged result.

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

## CLI Exit Codes Remapped {#cli-exit-codes-remapped}

Each failure kind now has its own exit code, defined in `CovLoupe::ExitCodes`.

| Code | 6.x | 7.0 |
|---|---|---|
| 0 | Success | Success, including a `validate` pass |
| 1 | Any error, including `validate` predicate returned falsy | Runtime error (missing, stale or corrupt coverage data, bad path) |
| 2 | `validate` predicate error, including missing or stale coverage data reported as "Predicate error"; invalid global options | Usage error: invalid options or arguments, invalid configuration |
| 3 | Not used | `validate`: predicate returned falsy (validation failed) |
| 4 | Not used | `validate`: error in the predicate itself (could not be loaded, not callable, or raised an exception); coverage-data errors it triggers exit 1 |

`validate` no longer reports coverage-data errors (missing, stale or corrupt coverage data) as "Predicate error". In 6.x they exited 2; they now print the normal error message and exit 1, like every other command.

Usage errors raised inside a subcommand (for example a global option placed after the subcommand, or missing `validate` arguments) previously exited 1 and now exit 2. Invalid global options also now show the subcommand and enum-value hints.

**Migration:** update CI scripts that test `validate` for exit 1 to test 3 (policy failed) and, if you distinguish them, 4 (predicate error). Scripts that treated exit 2 from `validate` as "stale or missing coverage" should test for 1 instead. A script that only checks for non-zero needs no change.

**Further reading:** [Exit Codes](../CLI_USAGE.md#exit-codes), [Release Notes](../../release_notes.md).

---

## Percentages Truncated, Not Rounded {#percentages-truncated-not-rounded}

Coverage percentages are truncated to two decimals instead of rounded, so incomplete coverage can never report `100.0`. In 6.x, 99,999 of 100,000 covered lines reported `100.0`. It now reports `99.99`.

This applies to every `percentage` value: library hashes, CLI output in all formats, and MCP tool payloads. A value can be up to `0.01` lower than in 6.x:

| Covered / Total | 6.x | 7.0 |
|---|---|---|
| 2 / 3 | `66.67` | `66.66` |
| 8 / 9 | `88.89` | `88.88` |
| 99,999 / 100,000 | `100.0` | `99.99` |

`CoverageReporter.report` now prints two decimals instead of one (`  99.95%` rather than `100.0%`).

**Migration:** check `validate` predicates and other scripts that compare a percentage to an exact or near-boundary value. For example, `percentage >= 66.67` no longer passes for 2 of 3 lines. Thresholds like `>= 100` or `>= 80` now hold only when coverage actually reaches that value.

---

## Staleness Values Renamed {#staleness-values-renamed}

Staleness states now have one name everywhere. The per-file `stale` value and the `project_totals` `stale.by_type` keys use the same names as the `list` arrays (`deleted_files`, `newer_files`, `length_mismatch_files`, `unreadable_files`):

| Where | 6.x | 7.0 |
|---|---|---|
| Per-file `stale` value (deleted source) | `"missing"` | `"deleted"` |
| Per-file `stale` value (unreadable source or failed check) | `"error"` | `"unreadable"` |
| Totals `files.with_coverage.stale.by_type` key | `missing_from_disk` | `deleted` |
| `totals` text output | `Stale: missing on disk = N` | `Stale: deleted = N` |
| `list` table legend | `Staleness: error, missing, newer, length_mismatch` | `Staleness: deleted, newer, length_mismatch, unreadable` |
| Library code testing for a deleted source | `StaleStatus::MISSING_FROM_DISK` | the string `"deleted"` (`StaleStatus` is internal) |

`"ok"`, `"newer"`, and `"length_mismatch"` are unchanged. "Missing" now only means absent coverage data (`missing_tracked_files`, `missing_from_coverage`) or an absent coverage timestamp (`timestamp_status: "missing"`). `CoverageModel#staleness_for` returns `"unreadable"` (was `"error"`) when the staleness check itself fails. `StaleStatus.normalize` now rejects `"missing"` and `"error"`.

This applies to library hashes, CLI output in all formats, and MCP tool payloads.

**Migration:** replace `stale == "missing"` checks with `"deleted"` and `stale == "error"` with `"unreadable"`, and read `by_type["deleted"]` instead of `by_type["missing_from_disk"]`. Replace `StaleStatus::MISSING_FROM_DISK` with the string `"deleted"` rather than `StaleStatus::DELETED`, since `StaleStatus` is internal as of 7.0 (see [Public API Declared](#public-api-declared)). Update `validate` predicates and scripts that parse the `totals` or `list` text output the same way.

## Library Results Use Project-Relative Paths {#library-results-use-project-relative-paths}

In 6.x, `CoverageModel#list`, `#summary_for`, `#uncovered_for`, `#detailed_for`, and `#raw_for` returned absolute file paths, while the CLI and MCP server reported project-relative ones; `CoverageModel#relativize` converted library results to the relative form. In 7.0 the library returns the same paths as the CLI and MCP server, so every payload has one shape. A path inside the project root is relative to the root; a path outside it stays absolute. This applies to every `file` value, including the `list` `files` and `skipped_files` rows. The other `list` path arrays (`missing_tracked_files`, `newer_files`, `deleted_files`, `length_mismatch_files`, and `unreadable_files`) were already relative for files inside the root, but showed files outside it as `../` paths; they now show those as absolute paths, in the library, CLI, and MCP output alike. Staleness errors change the same way: `CoverageDataStaleError#file_path`, the `CoverageDataProjectStaleError` path arrays, and the error messages report files outside the root as absolute paths. A relative path whose first directory starts with `~` is reported with a `./` prefix (for example `./~vendor/a.rb`) in all modes, so `File.expand_path` does not treat it as a home directory. On input, relative `coverage.json` keys and `format_table` row paths starting with `~` resolve to a directory under the root. In 6.x, such relative `.resultset.json` keys were expanded as home directories (or raised for an unknown user), and such row paths were used as written, so no `tracked_globs` pattern matched them and the row was dropped; query path arguments and `tracked_globs` still follow `File.expand_path`, so write `./~vendor/a.rb` to name such a directory there. `CoverageModel#relativize` is removed. `CoverageModel#format_table` called without rows now shows relative paths too (it showed absolute paths in 6.x). `validate` predicates receive library results, so a predicate that prints `f['file']` now prints relative paths. Table rows with equal coverage are ordered by absolute path, as in `list`; in 6.x the CLI and MCP tables ordered them by the displayed path, so ties involving files outside the root may order differently. Otherwise CLI and MCP output is unchanged, and `CoverageReporter.report` prints the same text apart from the `./~` prefix.

The path arguments the methods accept are unchanged: absolute paths and paths relative to the root both work, so a `file` value from one result can be passed straight to another query.

**Before (v6.x):**
```ruby
model = CovLoupe::CoverageModel.new(root: '/path/to/project')
model.summary_for('lib/foo.rb')['file']
# => "/path/to/project/lib/foo.rb"
model.relativize(model.summary_for('lib/foo.rb'))['file']
# => "lib/foo.rb"
```

**After (v7.0):**
```ruby
model.summary_for('lib/foo.rb')['file']
# => "lib/foo.rb"
```

**Migration:** remove `model.relativize(...)` calls and use the results directly. Use `File.expand_path(path, model.root)` if you need absolute paths; `CoverageModel#root` is public in 7.0 and returns the absolute project root the model resolved. Code that matched paths by an absolute prefix (for example `f['file'].start_with?(File.expand_path('lib', root))`) should match the relative form instead (`f['file'].start_with?('lib/')`).

## `project_validate` Requires `--allow-code-predicates` {#project_validate-requires---allow-code-predicates}

The MCP server no longer registers `project_validate` by default. It runs Ruby predicates that the MCP client writes, with the server's full privileges, outside any sandbox or approval prompt the client applies to shell commands. In 7.0 the server registers it only when started with `--allow-code-predicates`. Without the flag, `project_validate` is absent from `tools/list` and the `help` tool's listing, and calling it returns a JSON-RPC `-32602` ("Invalid params") error whose `data` is `"Tool not found: project_validate"`, instead of a result.

The CLI `validate` subcommand is unchanged and needs no flag.

**Migration:** if you use `project_validate` and accept the risk, add `--allow-code-predicates` to the server's arguments, e.g. `"args": ["-m", "mcp", "--allow-code-predicates"]`. Otherwise, run `cov-loupe validate` from a shell, or ask the client to apply your criteria to `project_coverage` output.

## Public API Declared {#public-api-declared}

In 6.x, the Library API guide's "API Boundary and Compatibility" section named `CovLoupe.run`, `CoverageModel`, and eight `CoverageModel` methods as supported, and promised to keep them compatible "as practical" across minor and patch releases. Other guides and migration notes, though, used many more classes, including internal ones renamed earlier in this guide. 7.0 replaces that section with [Public API and Versioning](../LIBRARY_API.md#public-api-and-versioning), which defines the public surface across the library, structured output, CLI, and MCP server, and commits to Semantic Versioning for it.

For the Ruby library, the source defines the public API: classes, modules, methods, and constants tagged `@api public` are public, and those tagged `@api private` are internal, including the internal members of partly public classes such as `CoverageModel` and the context object. The public parts include `CovLoupe.run`, `CoverageModel`, `PayloadSchema.schema_path`, the error classes, `ExitCodes`, `CoverageReporter.report`, and the context and logging methods. The payload schemas, CLI options and subcommands, and MCP tools and their arguments are public too. Everything else is internal and may change in any release. That includes classes renamed earlier in this guide, such as `Resolvers::CoverageFilePathResolver`, `CoverageRepository`, `CoverageJsonLoader`, `AppConfig`, and `StaleStatus`. Human-readable text (tables, text output, error message wording) is also outside the public API; structured output is covered through its `schema_version`.

Three internal constants are now private constants, so referencing them from outside the gem raises `NameError`: `CoverageModel::RELATIVIZER_SCALAR_KEYS`, `CoverageModel::RELATIVIZER_ARRAY_KEYS`, and `CovLoupe::StalenessFormatterMixin`.

Error handlers (`ErrorHandler`, `ErrorHandlerFactory`, `CovLoupe.error_handler`, `error_handler=`, and the `error_handler:` keyword of `create_context`) are internal, because library calls raise exceptions and never consult the context's configured handler. `create_context` no longer requires `error_handler:`, so library code can call `CovLoupe.create_context(log_target: ...)`; existing calls that pass it keep working. Nothing else changed behavior.

**Migration:** if you call anything tagged `@api private`, or otherwise outside [Public API and Versioning](../LIBRARY_API.md#public-api-and-versioning), move to a public equivalent (for example, compare staleness strings such as `"deleted"` instead of `StaleStatus::DELETED`, and use `CovLoupe.run` instead of instantiating `CoverageCLI`), or pin cov-loupe to an exact version. If the public API doesn't cover your use, open an issue.

## `--output-chars ascii` No Longer Changes Data {#output-chars-ascii-no-longer-changes-data}

In 6.x, ASCII mode (`-O ascii`, the MCP `output_chars: "ascii"` argument, the library's `output_chars: :ascii`, or `default` when it picks ASCII mode for a terminal that does not use UTF-8) produced ASCII-only output by rewriting the text: accented Latin letters and some symbols were transliterated (`é` became `e`, `€` became `EUR`, `→` became `->`), and every other non-ASCII character became `?`. That altered user data such as file paths, source lines and error messages.

In 7.0, ASCII mode changes only what cov-loupe draws itself: table borders use `+ - |`, and covered source lines are marked `+` instead of `✓`. Data is shown exactly as it is in every mode, so text output in ASCII mode can contain non-ASCII characters. In ASCII mode, successful JSON payloads still escape non-ASCII characters as `\uXXXX`, which encodes the data without changing it.

**Migration:** if you relied on ASCII mode to guarantee ASCII-only text output, for example for a consumer that rejects other bytes, use JSON output in ASCII mode (`-O ascii -f json` in the CLI; `output_chars: "ascii"` with a JSON format for MCP tools), or transliterate the output yourself. Only successful JSON payloads are escaped, and only in ASCII mode: error messages (CLI stderr and MCP `Error: ...` results) and non-JSON formats such as tables and YAML are not. Otherwise no change is needed.
