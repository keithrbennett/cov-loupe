# Migrating to v7.0

[Back to Migration Guides](README.md)

This document describes the breaking changes introduced in version 7.0.0. Sections are ordered roughly by impact: first the changes that stop cov-loupe from running or finding coverage, then changes to CLI, CI, and MCP setups, then to structured output and predicates, then to the library API, and last narrow edge cases.

## Table of Contents

- [Short Options `-c` and `-n` Reassigned](#short-options--c-and--n-reassigned)
- [A Subcommand Is Required](#a-subcommand-is-required)
- [Ruby 3.3 or Later Required](#ruby-33-or-later-required)
- [Only `coverage.json` Is Read; SimpleCov 1.x Output Is Required](#only-coveragejson-is-read-simplecov-10-is-required)
- [`resultset` Names Removed from the CLI, MCP Tools, and Library API](#resultset-names-removed-from-the-cli-mcp-tools-and-library-api)
- [Only `coverage/coverage.json` Is Searched by Default](#only-coveragecoveragejson-is-searched-by-default)
- [CLI Exit Codes Remapped](#cli-exit-codes-remapped)
- [Logging Defaults, Target Probing, and Lazy File Creation](#logging-defaults-target-probing-and-lazy-file-creation)
- [`project_validate` Requires `--allow-code-predicates`](#project_validate-requires---allow-code-predicates)
- [Tracked Globs Renamed to File Globs](#tracked-globs-renamed-to-file-globs)
- [MCP Tools No Longer Take `error_mode`](#mcp-tools-no-longer-take-error_mode)
- [Payload Keys Reshaped](#payload-keys-reshaped)
- [Staleness Values Renamed](#staleness-values-renamed)
- [Percentages Truncated, Not Rounded](#percentages-truncated-not-rounded)
- [Structured Output Has a Schema Version](#structured-output-has-a-schema-version)
- [Library Results Use Project-Relative Paths](#library-results-use-project-relative-paths)
- [Public API Declared](#public-api-declared)
- [Coverage Entry Lookup Errors Are `CoverageDataError`s](#coverage-entry-lookup-errors-are-coveragedataerrors)
- [Predicate and Unexpected Errors Reported Differently](#predicate-and-unexpected-errors-reported-differently)
- [Library `sort_order` Must Be `:ascending` or `:descending`](#library-sort_order-must-be-ascending-or-descending)
- [Totals Always Include `without_coverage`](#totals-always-include-without_coverage)
- [Totals Drop `without_coverage.by_type.unreadable`](#totals-drop-without_coverageby_typeunreadable)
- [Options Can Follow the Subcommand](#options-can-follow-the-subcommand)
- [`COV_LOUPE_OPTS` Is Parsed on Its Own](#cov_loupe_opts-is-parsed-on-its-own)
- [`--file-globs` Split Outside Braces and Brackets](#file-globs-split-outside-braces-and-brackets)
- [`--output-chars ascii` No Longer Changes Data](#output-chars-ascii-no-longer-changes-data)
- [Source and Predicate Files Are Read as UTF-8](#source-and-predicate-files-are-read-as-utf-8)

---

<a id="short-options--c-and--n-reassigned"></a>

## Short Options `-c` and `-n` Reassigned

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

## A Subcommand Is Required

In 6.x, `cov-loupe` with no subcommand ran `list`, also when only options were given (`cov-loupe -o a`). In 7.0 there is no default subcommand: such a command prints nothing on stdout, exits 2 (usage error), and reports on stderr:

```
No subcommand given. To show the coverage table, run 'cov-loupe list' (or 'cov-loupe l'). Valid subcommands: list, summary, raw, uncovered, detailed, totals, validate
```

**Before (v6.x):**

```sh
cov-loupe
cov-loupe -S true -g "lib/**/*.rb"
```

**After (v7.0):**

```sh
cov-loupe list
cov-loupe -S true -g "lib/**/*.rb" list
```

**Migration:**

- Add `list` (or `l`) to every invocation that has no subcommand: scripts, CI steps, shell aliases, and agent permission rules. A CI check such as `cov-loupe -S true` now fails with exit status 2 whatever the coverage, so it no longer passes or fails on staleness until `list` is added.
- No setting restores the old default: `COV_LOUPE_OPTS` may contain only options, not a subcommand (see [`COV_LOUPE_OPTS` Is Parsed on Its Own](#cov_loupe_opts-is-parsed-on-its-own)). A shell alias that already supplies the options, such as `alias clp='cov-loupe -R path/to/project'`, keeps working; type the subcommand after it (`clp list`).
- Invocations that only print and exit (`--help`, `--version`, `--path-for`) and MCP mode (`-m mcp`) take no subcommand and are unchanged.

## Ruby 3.3 or Later Required

cov-loupe 7.0 requires Ruby 3.3 or later; 6.x supported Ruby 3.2, which has reached end of life. The gemspec's `required_ruby_version` is now `>= 3.3`, so Bundler and RubyGems will not install 7.0 on Ruby 3.2, and the `cov-loupe` executable exits with an error if run under an older Ruby (only `-v`/`--version` still works).

**Migration:** upgrade to Ruby 3.3 or later before upgrading cov-loupe, or stay on 6.x while you remain on Ruby 3.2.

<a id="only-coveragejson-is-read-simplecov-10-is-required"></a>

## Only `coverage.json` Is Read; SimpleCov 1.x Output Is Required

cov-loupe now reads a single input: `coverage.json`, the output of SimpleCov's JSON formatter. SimpleCov 1.0.0 and later write it alongside the HTML report by default, and its shape is fixed by a versioned JSON schema in the SimpleCov repository.

`.resultset.json`, SimpleCov's internal merge cache, is no longer read.

cov-loupe no longer depends on the `simplecov` gem (6.x declared `simplecov >= 0.21`), so installing cov-loupe neither installs SimpleCov nor constrains your project's SimpleCov version. Instead, each load checks `meta.schema_version` in `coverage.json` (SimpleCov's output format version, e.g. `"1.0"`). Any 1.x is accepted; a missing value or another major version fails with a message naming the file and the value found, for example:

```
Unsupported coverage.json format (meta.schema_version: nil) in /app/coverage/coverage.json; cov-loupe requires format 1.x (written by SimpleCov 1.0 and later)
```

When `meta.simplecov_version` is present, the message also includes it.

This also rejects `coverage.json` files written for SimpleCov 0.x by the separate `simplecov_json_formatter` gem, which have no `schema_version`. Upgrade SimpleCov to 1.x to produce a supported file.

A `coverage.json` that lists files but has line data for none of them, as written when SimpleCov runs with `disable_coverage :line`, is also rejected on load with `CorruptCoverageDataError`, so the CLI exits non-zero. Previously every file was skipped and `list` and `totals` exited 0. Re-enable line coverage (`enable_coverage :line`) to read it.

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
- Replace any `--resultset` / `-r` argument (on the command line, in `COV_LOUPE_OPTS`, or in MCP server `args`) with `--coverage-file` / `-c`, and any `resultset:` keyword with `coverage_file:`, naming `coverage.json` or the directory containing it. See [`resultset` Names Removed](#resultset-names-removed-from-the-cli-mcp-tools-and-library-api) for the full list of renames.
- If you cannot upgrade SimpleCov, stay on cov-loupe 6.x, which reads `.resultset.json`.

**Error message change:** the not-found message is now `Could not find coverage.json under "<root>"; run tests or set --coverage-file option`, and a directory argument without one raises `No coverage.json found in directory: <dir>`. Scripts matching the old `Could not find .resultset.json under "<root>"; run tests or set --resultset option` text must be updated.

**Staleness output change:** the file line in stale-coverage errors now reads `Coverage file - <path>` instead of `Resultset - <path>`.

## `resultset` Names Removed from the CLI, MCP Tools, and Library API

v7.0 replaces every `resultset` name in the CLI, MCP tools, and library API with a `coverage_file` name. This is a single clean break: the old names are removed outright, with no deprecation period and no aliases.

| Removed | Use instead |
| --- | --- |
| `--resultset PATH` | `--coverage-file PATH` (short form `-c`; see [Short Options `-c` and `-n` Reassigned](#short-options--c-and--n-reassigned)) |
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
| `CoverageRepository.new(resultset_path:)` | `CoverageRepository.new(coverage_file:)` |
| `CoverageRepository#resultset_path` | `#resolved_coverage_file` |

Of these, only the CLI option, the MCP argument, the `CoverageModel` names, `CoverageReporter.report(coverage_file:)`, and the error classes and readers are public in 7.0. The resolver, loader, repository, and `AppConfig` names are internal, so they may change again in any release; see [Public API Declared](#public-api-declared).

**Before (v6.x):**

```sh
cov-loupe --resultset coverage list      # worked
```

```ruby
begin
  model = CovLoupe::CoverageModel.new(resultset: 'coverage')
rescue CovLoupe::ResultsetNotFoundError
  # ...
end
```

**After (v7.0):**

```sh
cov-loupe --coverage-file coverage list  # or: cov-loupe -c coverage list
```

```ruby
begin
  model = CovLoupe::CoverageModel.new(coverage_file: 'coverage')
rescue CovLoupe::CoverageFileNotFoundError
  # ...
end
```

**Migration:**

- Replace every name in the left column with the one on the right. `--resultset` on the command line (including in `COV_LOUPE_OPTS` and MCP server `args`) now fails as an unknown option; the `resultset` MCP tool argument is rejected as an unexpected argument.
- `ResultsetLoader.load(resultset_path:)` and `ResultsetLoader.new(resultset_path:, logger:)` become `CoverageJsonLoader.load(resolved_coverage_file:)` and `CoverageJsonLoader.new(resolved_coverage_file:, logger:)`. They return a `Result` with `coverage_map`, `timestamp`, and `recorded_root` (`meta.root`). The `suite_names` member of the old `ResultsetLoader::Result` is gone, since `coverage.json` is a single merged result.

## Only `coverage/coverage.json` Is Searched by Default

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

**Further reading:** [Configuring the Coverage File](../../../README.md#configuring-the-coverage-file), [SimpleCov Integration](../../dev/arch-decisions/simplecov-integration.md), [Release Notes](../../../RELEASE_NOTES.md).

## CLI Exit Codes Remapped

Each failure kind now has its own exit code, defined in `CovLoupe::ExitCodes`.

| Code | 6.x | 7.0 |
|---|---|---|
| 0 | Success | Success, including a `validate` pass |
| 1 | Any error, including `validate` predicate returned falsy | Runtime error (missing, stale or corrupt coverage data, bad path) |
| 2 | `validate` predicate error, including missing or stale coverage data reported as "Predicate error"; invalid global options | Usage error: invalid options or arguments, invalid configuration |
| 3 | Not used | `validate`: predicate returned falsy (validation failed) |
| 4 | Not used | `validate`: error in the predicate itself (could not be loaded, not callable, or raised an exception); coverage-data errors it triggers exit 1 |

`validate` no longer reports coverage-data errors (missing, stale or corrupt coverage data) as "Predicate error". In 6.x they exited 2; they now print the normal error message and exit 1, like every other command.

Usage errors raised inside a subcommand (for example unexpected arguments, or missing `validate` arguments) previously exited 1 and now exit 2. Invalid global options also now show the subcommand and enum-value hints.

**Migration:** update CI scripts that test `validate` for exit 1 to test 3 (policy failed) and, if you distinguish them, 4 (predicate error). Scripts that treated exit 2 from `validate` as "stale or missing coverage" should test for 1 instead. A script that only checks for non-zero needs no change.

**Further reading:** [Exit Codes](../CLI_USAGE.md#exit-codes), [Release Notes](../../../RELEASE_NOTES.md).

## Logging Defaults, Target Probing, and Lazy File Creation

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
case differences, surrounding whitespace, and (in the library) the symbol `:stderr`
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

<a id="project_validate-requires---allow-code-predicates"></a>

## `project_validate` Requires `--allow-code-predicates`

The MCP server no longer registers `project_validate` by default. It runs Ruby predicates that the MCP client writes, with the server's full privileges, outside any sandbox or approval prompt the client applies to shell commands. In 7.0 the server registers it only when started with `--allow-code-predicates`. Without the flag, `project_validate` is absent from `tools/list` and the `help` tool's listing, and calling it returns a JSON-RPC `-32602` ("Invalid params") error whose `data` is `"Tool not found: project_validate"`, instead of a result.

The CLI `validate` subcommand needs no such flag.

**Migration:** if you use `project_validate` and accept the risk, add `--allow-code-predicates` to the server's arguments, e.g. `"args": ["-m", "mcp", "--allow-code-predicates"]`. Otherwise, run `cov-loupe validate` from a shell, or ask the client to apply your criteria to `project_coverage` output.

## Tracked Globs Renamed to File Globs

"Tracked" could be read as git-tracked files, and SimpleCov 1.x no longer uses the word (`track_files` is deprecated in favor of `cover`). The option is now named for what it takes, and the old names are removed, with no alias:

| Where | 6.x | 7.0 |
|---|---|---|
| CLI option | `-g`/`--tracked-globs` | `-g`/`--file-globs` |
| Library keywords (`CoverageModel.new`, `list`, `format_table`, `project_totals`) | `tracked_globs:` | `file_globs:` |
| MCP tool argument (`project_coverage`, `project_coverage_totals`) | `tracked_globs` | `file_globs` |
| `project_totals` payload | `'tracking' => { 'enabled' => Boolean, 'globs' => [...] }` | `'file_globs' => [...]` (empty when none were given) |
| CLI `totals` text | `Tracked globs:` / `Tracked globs: (tracking disabled)` | `File globs:` / `File globs: (none)` |

`--f` no longer abbreviates `--format`: it is now a prefix of both `--format` and `--file-globs`, so it fails with `ambiguous option: --f`. Use `-f` or `--format`.

What the option does is unchanged: it limits project results to matching files, and reports matching files that have no coverage data.

**Migration:** replace `--tracked-globs` with `--file-globs` in scripts, `COV_LOUPE_OPTS` and MCP server arguments (`-g` is unchanged); replace the `tracked_globs:` keyword and MCP argument with `file_globs`; and replace `totals['tracking']['enabled']` with `totals['file_globs'].any?` and `totals['tracking']['globs']` with `totals['file_globs']`. The old CLI option is now an `invalid option` usage error, the old keyword raises `ArgumentError` (`unknown keyword`), and the old MCP argument is rejected as a "disallowed additional property".

## MCP Tools No Longer Take `error_mode`

In 6.x, every MCP tool accepted an `error_mode` argument (`off`, `log`, or `debug`) that set how much the server logged about a failed call. How much the server writes to its own log is the server operator's choice, not the client's, so 7.0 removes the argument. Every call uses the server's `--error-mode` (`log` unless set). A call that still passes `error_mode` fails with `isError: true`, reporting it as a disallowed additional property. Error responses to the client are unchanged; the mode only ever affected server-side logging.

**Migration:** remove `error_mode` from MCP tool calls. To change the logging, start the server with `--error-mode off|log|debug` (for example in the MCP client's server configuration).

## Payload Keys Reshaped

Line metrics now have one flat shape in every payload, and keys that meant different things in different payloads were renamed. This applies to library hashes, structured CLI output, and MCP tool payloads. `list` rows keep every key they had, so code that reads `list['files']` is unaffected.

Elsewhere, an old key now reads as `nil`. That usually raises an error, but code that converts it (`.to_f`, `.to_i`), uses `dig`, or supplies a `fetch` default silently gets `0` or `nil`, so search your code and saved predicates for the old names.

| Payload | 6.x | 7.0 |
|---|---|---|
| `summary_for`, `uncovered_for`, `detailed_for` (CLI `summary`/`uncovered`/`detailed`, MCP `file_coverage_summary`/`file_uncovered_lines`/`file_coverage_detailed`) | `'summary' => { 'covered', 'total', 'percentage' }` | top-level `'covered'`, `'uncovered'`, `'total'`, `'percentage'` |
| `uncovered_for` | `'uncovered' => [line numbers]` | `'uncovered_lines' => [line numbers]`; `'uncovered'` is now the count |
| `raw_for` (CLI `raw`, MCP `file_coverage_raw`) | `'lines' => [hit counts]` | `'line_hits' => [hit counts]`, so `'lines'` always means `detailed_for`'s per-line objects; the CLI `raw` table's `Coverage` column is now `Hits` |
| `project_totals` (CLI `totals`, MCP `project_coverage_totals`) | `'lines' => { 'covered', 'uncovered', 'total', 'percentage', 'included_files', 'excluded_files' }` | top-level `'covered'`, `'uncovered'`, `'total'`, `'percentage'`; use `file_counts.with_coverage.ok` and `.stale.total` for the file counts |
| `project_totals` | `'files' => { ... }` | `'file_counts' => { ... }` (same contents) |
| `project_totals` | `'tracking' => { 'enabled', 'globs' }` | `'file_globs' => [...]`; see [Tracked Globs Renamed to File Globs](#tracked-globs-renamed-to-file-globs) |
| `project_totals` | `without_coverage.by_type.missing_from_coverage` | `without_coverage.by_type.not_in_coverage` |
| `project_totals` | `without_coverage.by_type.unreadable` | removed; such files are counted under `with_coverage.stale.by_type.unreadable`, or under `without_coverage.by_type.skipped` if their coverage data is invalid; see [Totals Drop `without_coverage.by_type.unreadable`](#totals-drop-without_coverageby_typeunreadable) |
| `list` (CLI `list`, MCP `project_coverage`) | `'missing_tracked_files'` | `'not_in_coverage_files'` |
| `CoverageDataProjectStaleError` | `#missing_files`, `missing_files:` keyword | `#not_in_coverage_files`, `not_in_coverage_files:` keyword |
| `list` rows | `'covered'`, `'total'`, `'percentage'`, `'stale'` | unchanged, plus `'uncovered'` |
| CLI and MCP `list` / `project_coverage` | `'counts' => { 'total', 'ok', 'stale' }` | removed; count the rows, or use `project_totals['file_counts']['with_coverage']` |
| Library `summary_for`, `uncovered_for`, `detailed_for`, `raw_for` | no `'stale'` (the CLI and MCP added it) | `'stale'` included, as in CLI and MCP output |
| MCP `help` `resources` | `"docs-local"` | `"docs_local"`; the CLI's `--path-for docs-local` is unchanged |

A `summary_for` result is now the file's `list` row plus [`schema_version`](#structured-output-has-a-schema-version).

**Migration:**

- Replace `result['summary']['percentage']` (and `covered`/`total`) with `result['percentage']`.
- Replace `project_totals['lines']['percentage']` with `project_totals['percentage']`, for example in a `validate` predicate: `->(m) { m.project_totals['percentage'].to_f >= 85 }`.
- Replace `uncovered_for(path)['uncovered']` with `['uncovered_lines']`.
- Replace `raw_for(path)['lines']` with `['line_hits']` (CLI `raw` JSON and MCP `file_coverage_raw` too). The old key is not aliased: it now reads as `nil`. Scripts that match the CLI `raw` table should look for the `Hits` column header (was `Coverage`).
- Replace `totals['files']` with `totals['file_counts']`, and `missing_from_coverage` with `not_in_coverage`.
- Replace `list['missing_tracked_files']` with `list['not_in_coverage_files']`, and `CoverageDataProjectStaleError#missing_files` with `#not_in_coverage_files`. "Missing" was ambiguous: it could also mean a file in the coverage data that is gone from disk, which is reported as `deleted`. Scripts that match CLI text should look for "Files not in coverage data" (was "Missing tracked files" in `list` and "Missing files" in stale-project errors) and "Not in coverage data =" (was "Missing from coverage =" in `totals`).
- Replace `lines['included_files']` with `file_counts['with_coverage']['ok']`, and `lines['excluded_files']` with `file_counts['with_coverage']['stale']['total']`.
- If you read `counts` from `list` JSON, count `files` rows by their `stale` value instead.
- Drop separate `model.staleness_for(path)` calls made only to complete a file query; read its `'stale'` key.

## Staleness Values Renamed

Staleness states now have one name everywhere. The per-file `stale` value and the `project_totals` `stale.by_type` keys use the same names as the `list` arrays (`deleted_files`, `newer_files`, `length_mismatch_files`, `unreadable_files`):

| Where | 6.x | 7.0 |
|---|---|---|
| Per-file `stale` value (deleted source) | `"missing"` | `"deleted"` |
| Per-file `stale` value (unreadable source or failed check) | `"error"` | `"unreadable"` |
| Totals `with_coverage.stale.by_type` key (under `file_counts` in 7.0; see [Payload Keys Reshaped](#payload-keys-reshaped)) | `missing_from_disk` | `deleted` |
| `totals` text output | `Stale: missing on disk = N` | `Stale: deleted = N` |
| `list` table legend | `Staleness: error, missing, newer, length_mismatch` | `Staleness: deleted, newer, length_mismatch, unreadable` |
| Library code testing for a deleted source | `StaleStatus::MISSING_FROM_DISK` | the string `"deleted"` (`StaleStatus` is internal) |

`"ok"`, `"newer"`, and `"length_mismatch"` are unchanged. "Missing" now only means an absent coverage timestamp (`timestamp_status: "missing"`). A file that matches the file globs but is absent from the coverage data is "not in coverage": `not_in_coverage_files` in `list` (`missing_tracked_files` in 6.x), counted as `not_in_coverage` in totals. `CoverageModel#staleness_for` returns `"unreadable"` (was `"error"`) when the staleness check itself fails. `StaleStatus.normalize` now rejects `"missing"` and `"error"`.

This applies to library hashes, CLI output in all formats, and MCP tool payloads.

**Migration:** replace `stale == "missing"` checks with `"deleted"` and `stale == "error"` with `"unreadable"`, and read `by_type["deleted"]` instead of `by_type["missing_from_disk"]`. Replace `StaleStatus::MISSING_FROM_DISK` with the string `"deleted"` rather than `StaleStatus::DELETED`, since `StaleStatus` is internal as of 7.0 (see [Public API Declared](#public-api-declared)). Update `validate` predicates and scripts that parse the `totals` or `list` text output the same way.

## Percentages Truncated, Not Rounded

Coverage percentages are truncated to two decimals instead of rounded, so incomplete coverage can never report `100.0`. In 6.x, 99,999 of 100,000 covered lines reported `100.0`. It now reports `99.99`.

This applies to every `percentage` value: library hashes, CLI output in all formats, and MCP tool payloads. A value can be up to `0.01` lower than in 6.x:

| Covered / Total | 6.x | 7.0 |
|---|---|---|
| 2 / 3 | `66.67` | `66.66` |
| 8 / 9 | `88.89` | `88.88` |
| 99,999 / 100,000 | `100.0` | `99.99` |

`CoverageReporter.report` now prints two decimals instead of one (`  99.95%` rather than `100.0%`).

**Migration:** check `validate` predicates and other scripts that compare a percentage to an exact or near-boundary value. For example, `percentage >= 66.67` no longer passes for 2 of 3 lines. Thresholds like `>= 100` or `>= 80` now hold only when coverage actually reaches that value.

## Structured Output Has a Schema Version

Every hash returned by a public `CoverageModel` coverage method, successful structured CLI payload (`-f json`, `pretty_json`, `yaml`, and the other non-table formats), and structured MCP tool payload now starts with top-level integer `"schema_version": 1`. The existing payload keys remain at the top level; there is no wrapper. For example, a file summary begins `{"schema_version":1,"file":"lib/foo.rb",...}`. MCP clients should check `result.isError` before parsing the tool content.

Library methods such as `CoverageModel#summary_for`, `#list`, and `#project_totals` now include this field, so saved JSON, YAML, or Marshal output carries the marker automatically. Table and text output, MCP `version` text, and error responses are unchanged. This version is separate from the gem version and from SimpleCov's `schema_version` in the input `coverage.json` file. See [Schema Version](../LIBRARY_API.md#schema-version) for the compatibility rules.

**Migration:** If a consumer compares exact top-level key sets or iterates every top-level key, account for `schema_version` before processing the coverage fields. Check that its value is `1` when reading saved payloads, and ignore other unknown keys.

## Library Results Use Project-Relative Paths

In 6.x, `CoverageModel#list`, `#summary_for`, `#uncovered_for`, `#detailed_for`, and `#raw_for` returned absolute file paths, while the CLI and MCP server reported project-relative ones; `CoverageModel#relativize` converted library results to the relative form. In 7.0 the library returns the same paths as the CLI and MCP server, so every payload has one shape: a path inside the project root is relative to the root, and a path outside it stays absolute. `CoverageModel#relativize` is removed.

In detail:

- **`file` values:** Every `file` value changes this way, including the `list` `files` and `skipped_files` rows.
- **Other `list` path arrays:** `missing_tracked_files` (now `not_in_coverage_files`), `newer_files`, `deleted_files`, `length_mismatch_files`, and `unreadable_files` were already relative for files inside the root, but showed files outside it as `../` paths. They now show those as absolute paths, in the library, CLI, and MCP output alike.
- **Staleness errors:** `CoverageDataStaleError#file_path`, the `CoverageDataProjectStaleError` path arrays, and the error messages also report files outside the root as absolute paths.
- **Paths starting with `~`:** A relative path whose first directory starts with `~` is reported with a `./` prefix (for example `./~vendor/a.rb`) in all modes, so `File.expand_path` does not treat it as a home directory. On input, relative `coverage.json` keys and `format_table` row paths starting with `~` resolve to a directory under the root. In 6.x, such relative `.resultset.json` keys were expanded as home directories (or raised for an unknown user), and such row paths were used as written, so no `tracked_globs` pattern matched them and the row was dropped. Query path arguments and `file_globs` (`tracked_globs` in 6.x) still follow `File.expand_path`, so write `./~vendor/a.rb` to name such a directory there.
- **`format_table`:** Called without rows, it now shows relative paths too (it showed absolute paths in 6.x).
- **`validate` predicates:** They receive library results, so a predicate that prints `f['file']` now prints relative paths.
- **Table order:** Table rows with equal coverage are ordered by absolute path, as in `list`. In 6.x the CLI and MCP tables ordered them by the displayed path, so ties involving files outside the root may order differently.

Otherwise CLI and MCP output is unchanged, and `CoverageReporter.report` prints the same text apart from the `./~` prefix and the two-decimal percentages described in [Percentages Truncated, Not Rounded](#percentages-truncated-not-rounded).

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

## Public API Declared

In 6.x, the Library API guide's "API Boundary and Compatibility" section named `CovLoupe.run`, `CoverageModel`, and eight `CoverageModel` methods as supported, and promised to keep them compatible "as practical" across minor and patch releases. Other guides and migration notes, though, used many more classes, including internal ones renamed earlier in this guide. 7.0 replaces that section with [Public API and Versioning](../LIBRARY_API.md#public-api-and-versioning), which defines the public surface across the library, structured output, CLI, and MCP server, and commits to Semantic Versioning for it.

For the Ruby library, the source defines the public API: classes, modules, methods, and constants tagged `@api public` are public, and those tagged `@api private` are internal, including the internal members of partly public classes such as `CoverageModel` and the context object. The public parts include `CovLoupe.run` and `CovLoupe.execute`, `CoverageModel`, `PayloadSchema.schema_path`, the error classes, `ExitCodes`, `CoverageReporter.report`, and the context and logging methods. The payload schemas, CLI options and subcommands, and MCP tools and their arguments are public too. Everything else is internal and may change in any release. That includes classes renamed earlier in this guide, such as `Resolvers::CoverageFilePathResolver`, `CoverageRepository`, `CoverageJsonLoader`, `AppConfig`, and `StaleStatus`. Human-readable text (tables, text output, error message wording) is also outside the public API; structured output is covered through its `schema_version`.

Three internal constants are now private constants, so referencing them from outside the gem raises `NameError`: `CoverageModel::RELATIVIZER_SCALAR_KEYS`, `CoverageModel::RELATIVIZER_ARRAY_KEYS`, and `CovLoupe::StalenessFormatterMixin`.

Error handlers (`ErrorHandler`, `ErrorHandlerFactory`, `CovLoupe.error_handler`, `error_handler=`, and the `error_handler:` keyword of `create_context`) are internal, because library calls raise exceptions and never consult the context's configured handler. `create_context` no longer requires `error_handler:`, so library code can call `CovLoupe.create_context(log_target: ...)`; existing calls that pass it keep working. Nothing else changed behavior.

**Migration:** if you call anything tagged `@api private`, or otherwise outside [Public API and Versioning](../LIBRARY_API.md#public-api-and-versioning), move to a public equivalent (for example, compare staleness strings such as `"deleted"` instead of `StaleStatus::DELETED`, and use `CovLoupe.run` instead of instantiating `CoverageCLI`), or pin cov-loupe to an exact version. If the public API doesn't cover your use, open an issue.

## Coverage Entry Lookup Errors Are `CoverageDataError`s

In 6.x, a file query (`summary_for`, `raw_for`, `uncovered_for`, `detailed_for`; CLI `summary` and the other file commands; the MCP file tools) for a path with no coverage entry raised `CovLoupe::FileError` ("No coverage entry found for ..."), and so did a path that matched several entries ("Multiple coverage entries match path ..."). That class also meant a source file that could not be read. These are coverage-data problems, not file problems, so 7.0 raises two new `CoverageDataError` subclasses instead:

| Case | 6.x | 7.0 |
|---|---|---|
| No coverage entry matches the path | `FileError` | `CoverageEntryNotFoundError` |
| Several coverage entries match the path | `FileError` | `AmbiguousCoverageEntryError` |

They are not `FileError` subclasses, so `rescue CovLoupe::FileError` no longer catches them. The message is unchanged, but its prefix in CLI and MCP output is now `Coverage data error:` (was `File error:`). The CLI exit code stays 1.

`CoverageModel#staleness_for` returned `"error"` (now `"unreadable"`; see [Staleness Values Renamed](#staleness-values-renamed)) for a path with no coverage entry, and for any other failed lookup, instead of raising. It now raises what the file queries raise for the same path: these two errors, a `CoverageDataError` (such as `CorruptCoverageDataError`) for a malformed entry, or a coverage-file error. It returns `"unreadable"` only when the source file could not be read or its staleness check failed.

**Migration:** replace `rescue CovLoupe::FileError` around file queries with `rescue CovLoupe::CoverageEntryNotFoundError` (and `AmbiguousCoverageEntryError` if you handle it), or rescue `CovLoupe::CoverageDataError` or `CovLoupe::Error` to catch both. Keep `rescue CovLoupe::FileError` where you handle unreadable or deleted files. Rescue around `staleness_for` calls whose path may not be in the coverage data, and stop treating its `"unreadable"` result as "not in coverage". Scripts that match CLI text should look for `Coverage data error: No coverage entry found`.

## Predicate and Unexpected Errors Reported Differently

While a predicate runs, only `PredicateError`, `CoverageDataError` and `FileError` now pass through unchanged. Any other error, including a `UsageError` or `ConfigurationError` that the predicate raises itself, becomes a `PredicateError` with the original attached. In the CLI such a predicate now exits 4 rather than 2; library callers rescue `PredicateError`; and the MCP `project_validate` tool reports `Predicate error: ...`.

An unexpected `ArgumentError` that reaches the error handler outside coverage loading is now an `UnknownError` ("An unexpected error occurred: ...", exit 1 in the CLI) instead of a `ConfigurationError` or `UsageError` ("Invalid configuration: ...", exit 2). Validation of user input still raises `UsageError` or `ConfigurationError` directly and is unaffected.

**Migration:** code that rescued `UsageError` or `ConfigurationError` from a predicate should rescue `PredicateError` (its `original_error` is the error the predicate raised). Scripts that matched "Invalid configuration" for an internal `ArgumentError` should treat exit 1 as the unexpected-error case.

## Library `sort_order` Must Be `:ascending` or `:descending`

In 6.x, `CoverageModel#list` and `CoverageModel#format_table` sorted descending only for the symbol `:descending` and ascending for any other value, including a misspelling, `nil`, and the string `'descending'`. In 7.0 they raise `ArgumentError` for anything but `:ascending` or `:descending`, before any staleness check. This applies to `validate` predicates too, since they receive a `CoverageModel`: a predicate that passes a string now fails with a predicate error (exit 4). The CLI `--sort-order` option and the MCP `sort_order` argument are unchanged.

| Library call | 6.x | 7.0 |
|---|---|---|
| `model.list(sort_order: 'ascending')` or `sort_order: nil` | ascending | `ArgumentError` |
| `model.list(sort_order: 'descending')` | ascending (silently wrong) | `ArgumentError` |
| `model.list(sort_order: :desc)` | ascending (silently wrong) | `ArgumentError` |
| `model.format_table(sort_order: 'a')` | ascending | `ArgumentError` |

**Migration:** in library code and predicates, pass `:ascending` or `:descending`, or omit `sort_order` for the default `:descending`. `to_sym` is enough only when the string is exactly `'ascending'` or `'descending'`: it turns any string into a symbol without checking it, so `'a'.to_sym` gives `:a`, which the library rejects. To accept the abbreviations and capitalization the CLI accepts, map the string yourself; this rejects anything else, including `nil`:

```ruby
SORT_ORDERS = { 'a' => :ascending, 'ascending' => :ascending,
                'd' => :descending, 'descending' => :descending }.freeze

sort_order = SORT_ORDERS.fetch(input.to_s.downcase) { raise ArgumentError, "bad sort order: #{input.inspect}" }
model.list(sort_order: sort_order)
```

## Totals Always Include `without_coverage`

In 6.x, `project_totals` (CLI `totals`, MCP `project_coverage_totals`) included `files.without_coverage` only when tracked globs were set. Without them, a coverage row skipped for invalid data, such as a file with only branch coverage, appeared nowhere in the totals, and `files.total` left it out. (7.0 renames `files` to `file_counts` and `missing_from_coverage` to `not_in_coverage`; see [Payload Keys Reshaped](#payload-keys-reshaped).)

In 7.0, `without_coverage` is always present, so skipped rows are always counted, and `file_counts.total` includes them. Its `not_in_coverage` count needs file globs: without them there is no list of files that should have coverage, so the count is `null` (`nil` in Ruby) rather than a `0` that would claim a check that did not happen. `without_coverage.total` adds up the counts that are not `null`. The CLI `totals` text always shows the "Without coverage" lines, with `Not in coverage data = n/a (no file globs)` when no globs are set.

| Payload | 6.x, no tracked globs | 7.0, no file globs |
|---|---|---|
| `files.without_coverage` (7.0: `file_counts.without_coverage`) | absent | `{ "total": N, "by_type": { "not_in_coverage": null, "skipped": N } }` |
| `files.total` (7.0: `file_counts.total`) | files with coverage rows only | files with coverage rows, plus skipped ones |

With file globs set, `without_coverage` was already present, so the payload changes only by the renames above and the removal described in [Totals Drop `without_coverage.by_type.unreadable`](#totals-drop-without_coverageby_typeunreadable).

**Migration:** code that tested whether `without_coverage` is present to tell if globs were set should check `file_globs.any?` instead. Code that adds up `by_type` values should skip `null` (for example `by_type.values.compact.sum` in Ruby), or read `without_coverage.total`.

## Totals Drop `without_coverage.by_type.unreadable`

In 6.x, when tracked globs were set, `project_totals` counted every unreadable file in `files.without_coverage.by_type.unreadable`. But only files with a coverage entry are read (to check staleness), so each such file was already counted elsewhere: as stale under `with_coverage` if it had a coverage row, or as `skipped` if its coverage data was invalid. It was counted twice, inflating `files.total`. Files matching the globs that have no coverage entry are never read, only listed, so they count as `not_in_coverage` whether readable or not.

7.0 removes `without_coverage.by_type.unreadable` and counts each unreadable file once, as stale or skipped. The CLI `totals` text drops `unreadable = N` from the "Without coverage" line.

**Migration:** code that reads `without_coverage.by_type.unreadable` should read `with_coverage.stale.by_type.unreadable` instead, plus `without_coverage.by_type.skipped` if it should also count files whose coverage data is invalid (skipped files are not distinguished by cause).

## Options Can Follow the Subcommand

In 6.x, global options had to come before the subcommand. In 7.0 they can also come after it, mixed with its arguments, so an agent permission rule such as `Bash(cov-loupe list:*)` can allow a subcommand with any options:

```sh
cov-loupe --format json summary lib/foo.rb   # 6.x and 7.0
cov-loupe summary lib/foo.rb --format json   # 7.0
```

`-m`/`--mode`, `--[no-]allow-code-predicates`, `-h`/`--help`, `-v`/`--version` and `-p`/`--path-for` still come only before the subcommand. These command lines change:

| Command line | 6.x | 7.0 |
|---|---|---|
| `cov-loupe summary -odd.rb` | `-odd.rb` is the path | `-odd.rb` is read as `-o dd.rb`: `invalid argument: -odd.rb`; write `cov-loupe summary -- -odd.rb` |
| `cov-loupe list -v` | prints the version | usage error: `-v must come before the subcommand` |
| `cov-loupe -m mcp list` | starts the MCP server; `list` is ignored | usage error |
| `COV_LOUPE_OPTS=list cov-loupe` | runs `list` | usage error: `COV_LOUPE_OPTS` may contain only options |
| `COV_LOUPE_OPTS=list cov-loupe -f json` | usage error (`-f` after the subcommand), exit 1 | usage error, as above, exit 2 |
| `cov-loupe -- list` | runs `list` | usage error: `--` is allowed only after a subcommand |

**Migration:** pass a path that starts with `-` after `--`. Move a subcommand out of `COV_LOUPE_OPTS` onto the command line. Remove a standalone `--` before the subcommand (not one that is an option's value, as in `-g --`), and any arguments after `-m mcp`.

<a id="cov_loupe_opts-is-parsed-on-its-own"></a>

## `COV_LOUPE_OPTS` Is Parsed on Its Own

In 6.x, the options in `COV_LOUPE_OPTS` and the command line were parsed in one pass, so an option at the end of `COV_LOUPE_OPTS` that needs a value took the first command-line argument as its value: `COV_LOUPE_OPTS="-f"` with `cov-loupe json list` printed JSON.

In 7.0, `COV_LOUPE_OPTS` is parsed on its own, before the command line, so such an option is an error (exit 2). That separation is what lets errors in `COV_LOUPE_OPTS` be reported as such:

```text
$ COV_LOUPE_OPTS="-f" cov-loupe json list
Error: missing argument: -f
Valid values for --format: a/amazing_print|i/inspect|j/json|J/pretty_json|p/puts|P/pretty_print|t/table|y/yaml
The error is in COV_LOUPE_OPTS ("-f"), which is read before the command line.
Run 'cov-loupe --help' for usage information.
```

**Migration:** if `COV_LOUPE_OPTS` ends with an option that relies on the command line for its value, move the value into `COV_LOUPE_OPTS`, or move the option to the command line. Otherwise no change is needed.

<a id="file-globs-split-outside-braces-and-brackets"></a>

## `--file-globs` Split Outside Braces and Brackets

In 6.x, the CLI split the `-g`/`--tracked-globs` value (now `--file-globs`; see [Tracked Globs Renamed to File Globs](#tracked-globs-renamed-to-file-globs)) on every comma. A brace pattern such as `-g 'app/{models,controllers}/**/*.rb'` became two invalid globs that matched nothing, without an error, and an empty item (`-g 'a,,b'`) made project-level commands such as `list` and `totals` fail with `no implicit conversion of nil into String`.

In 7.0:

- The value is split only on commas outside `{...}` and `[...]` and, except on Windows, not on a backslash-escaped comma (`\,`). Empty items are ignored.
- An unclosed `{`, or an unclosed `[` outside braces, is a usage error (exit 2) for every command, the per-file ones included, whether the value comes from the command line or `COV_LOUPE_OPTS`. It also stops the MCP server from starting. Such a value used to run with exit 0: it was split at every comma, the fragment holding the bracket matched nothing on CRuby (JRuby read an unmatched `{` literally), and the other fragments still applied.

The MCP `file_globs` argument and the Ruby API take their patterns as an array (the Ruby API also takes one string, used as a single pattern) and do not split them, so this change does not affect them.

**Migration:** values without braces, brackets, or backslashes need no change. Fix any unclosed `{` or `[` the new error reports. To match a literal `[`, write `[[]` (or `\[`, except on Windows); to match a literal `{`, write `\{`, quoted so the shell keeps the backslash (not possible on Windows). If a value relied on splitting at a comma inside braces or brackets, or after a backslash, write those patterns separately. See [`--file-globs`](../CLI_USAGE.md#file-globs).

<a id="output-chars-ascii-no-longer-changes-data"></a>

## `--output-chars ascii` No Longer Changes Data

In 6.x, ASCII mode (`-O ascii`, the MCP `output_chars: "ascii"` argument, the library's `output_chars: :ascii`, or `default` when it picks ASCII mode for a terminal that does not use UTF-8) produced ASCII-only output by rewriting the text: accented Latin letters and some symbols were transliterated (`é` became `e`, `€` became `EUR`, `→` became `->`), and every other non-ASCII character became `?`. That altered user data such as file paths, source lines and error messages.

In 7.0, ASCII mode changes only what cov-loupe draws itself: table borders use `+ - |`, and covered source lines are marked `+` instead of `✓`. Data is shown exactly as it is in every mode, so text output in ASCII mode can contain non-ASCII characters. In ASCII mode, successful JSON payloads still escape non-ASCII characters as `\uXXXX`, which encodes the data without changing it.

**Migration:** if you relied on ASCII mode to guarantee ASCII-only text output, for example for a consumer that rejects other bytes, use JSON output in ASCII mode (`-O ascii -f json` in the CLI; `output_chars: "ascii"` with a JSON format for MCP tools), or transliterate the output yourself. Only successful JSON payloads are escaped, and only in ASCII mode: error messages (CLI stderr and MCP `Error: ...` results) and non-JSON formats such as tables and YAML are not. Otherwise no change is needed.

## Source and Predicate Files Are Read as UTF-8

In 6.x, source files (for source display with `--source`) and `validate` predicate files were read in the locale's encoding. A file in a non-UTF-8 encoding such as ISO-8859-1 therefore worked under a matching locale, while under the C locale (`LANG=C`) predicate files with non-ASCII string literals and JSON source output with non-ASCII characters failed.

In 7.0 they are always read as UTF-8, Ruby's default source encoding, whatever the locale. Non-ASCII UTF-8 files now work under every locale, including `LANG=C`. A file in another encoding is no longer decoded with the locale:

- Source display shows its non-ASCII bytes raw in the table and escaped (such as `\xE9`) in the other text formats.
- JSON or YAML source output fails with `Source file is not valid UTF-8`.
- A predicate file fails to evaluate if it has non-ASCII characters outside comments, such as in string literals.

**Migration:** if your source or predicate files are UTF-8 (or ASCII), no change is needed. Otherwise convert them to UTF-8, for example with `iconv -f ISO-8859-1 -t UTF-8`. A magic comment such as `# encoding: ISO-8859-1` lets a predicate file parse, but its non-ASCII strings are then in that encoding and do not match the UTF-8 paths in the coverage data, so converting is the reliable fix.
