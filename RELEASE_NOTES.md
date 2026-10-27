# Release Notes

[Back to main README](README.md)


## Unreleased

### Breaking

- **`off` disables logging.** `--log-file off` (any case, surrounding whitespace ignored),
  `COV_LOUPE_OPTS`, and the Ruby API now treat `off` as the reserved word that disables
  logging, like `stderr` is reserved. The old `':off'` spelling is no longer recognized and
  would now be used as a log file name, so replace it with `off`. The symbol `:off` is
  accepted (it previously raised `CovLoupe::LoggingError`). A log file literally named
  `off` must now be written `./off`. A disabled logger's `target` is now `'off'` instead of
  `':off'`; `CovLoupe.default_log_file`, `CovLoupe.active_log_file`, and
  `AppContext#log_target` return the value you set, unchanged. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md).
- **Public API declared.** Only the public API defined in
  [Public API and Versioning](docs/user/LIBRARY_API.md#public-api-and-versioning) follows
  Semantic Versioning: Ruby classes and methods tagged `@api public` in the source (among
  them `CovLoupe.run`, `CoverageModel`, the error classes, and `ExitCodes`), the shipped
  payload schemas, CLI options and subcommands, and MCP tool names and arguments. Classes
  and methods tagged `@api private`, and human-readable text output, may change in any
  release. `CoverageModel::RELATIVIZER_SCALAR_KEYS`,
  `CoverageModel::RELATIVIZER_ARRAY_KEYS`, and `CovLoupe::StalenessFormatterMixin` are now
  private constants and raise `NameError` when referenced from outside. Error handlers
  (`ErrorHandler`, `ErrorHandlerFactory`, `CovLoupe.error_handler`, `error_handler=`) are
  internal because library calls never consult the context's configured handler, and
  `CovLoupe.create_context` no longer requires `error_handler:`. Nothing else changed
  behavior. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#public-api-declared).
- **Library results use project-relative paths.** `CoverageModel#list`, `#summary_for`,
  `#uncovered_for`, `#detailed_for`, and `#raw_for` now return the same paths as the CLI and
  MCP server: relative to the project root, or absolute for files outside it (6.x returned
  absolute `file` values). `CoverageModel#relativize` is removed; use
  `File.expand_path(path, model.root)` if you need absolute paths (`CoverageModel#root` is a
  new public reader). `validate` predicates receive these results, so they now see relative
  paths too. In all modes, the `list` path arrays (`newer_files`, `deleted_files`, and so on)
  and staleness errors (`CoverageDataStaleError#file_path`, the
  `CoverageDataProjectStaleError` arrays, and their messages) now report files outside the
  root as absolute paths instead of `../` paths, and a relative path whose first directory
  starts with `~` is reported with a `./` prefix (for example `./~vendor/a.rb`), including in
  `CoverageReporter.report` text. Relative `coverage.json` keys and `format_table` row paths
  starting with `~` now resolve to a directory under the root (6.x expanded such `.resultset.json`
  keys as home directories, raising for an unknown user, and used such row paths as written, so
  no `tracked_globs` pattern matched them);
  query path arguments and `tracked_globs` still follow `File.expand_path`. Table rows with
  equal coverage are ordered by absolute path, as in `list`, so ties involving files outside
  the root may order differently. CLI and MCP output is otherwise unchanged. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#library-results-use-project-relative-paths).
- **`project_validate` is opt-in in the MCP server.** The server now registers
  `project_validate` only when started with `--allow-code-predicates`. Without it, the tool is
  absent from `tools/list` and `help`, and calls return a JSON-RPC `-32602` error whose `data`
  is `"Tool not found: project_validate"`. The tool runs client-supplied Ruby with full
  privileges, outside any sandbox the MCP client applies to shell commands. The CLI `validate` subcommand is unchanged. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#project_validate-requires---allow-code-predicates).
- **Staleness values renamed.** Per-file `stale` values `"missing"` and `"error"` are now
  `"deleted"` and `"unreadable"`, and the totals `stale.by_type` key `missing_from_disk` is now
  `deleted`, matching the `deleted_files`/`unreadable_files` list arrays. Text output follows:
  `totals` prints `Stale: deleted = N` (was `missing on disk`), and the `list` legend uses the
  new names. Code that used the internal constant `StaleStatus::MISSING_FROM_DISK` should
  compare against the string `"deleted"`. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#staleness-values-renamed).
- **Ruby 3.3 or later is required.** The minimum supported Ruby is now 3.3 (was 3.2).
  Ruby 3.2 has reached end of life, and 3.3 is the oldest Ruby still maintained. See [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#ruby-33-or-later-required).
- **CLI exit codes were remapped.** `validate` now exits `3` when the predicate
  returns a falsy value (was `1`) and `4` when the predicate cannot be loaded or
  raises an error of its own (was `2`); coverage-data errors it triggers exit
  `1`. `validate` also no longer labels missing or stale coverage data as a
  "Predicate error" (previously exit `2`); it now exits `1` with the normal error
  message. Predicate errors now go through the central error handler, so they are
  logged like other CLI errors: to the log file when `--log-file` is a file (not to
  the default `stderr` target, where the message is already printed). Usage errors (invalid
  options or arguments, invalid configuration, misplaced global options) now
  consistently exit `2`; some were `1`. Exit `1` is reserved for runtime errors
  such as missing or stale coverage data. Invalid global options now also get
  the enum-value and subcommand suggestions previously unreachable from the real
  executable. Scripts that test `validate` for `$? -eq 1` must be updated. Codes are defined in
  `CovLoupe::ExitCodes`. See [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#cli-exit-codes-remapped).
- **Predicate evaluation wraps more errors in `PredicateError`.** `PredicateEvaluator` now
  re-raises only `PredicateError`, `CoverageDataError` and `FileError` unchanged; any other
  error raised while a predicate runs, including a `UsageError` or `ConfigurationError`
  the predicate raises itself, becomes a `PredicateError` with the original attached. This
  also applies to library callers and to the MCP `project_validate` tool, which reports
  such errors as `Predicate error: ...`.
- **Unexpected `ArgumentError`s are reported as unexpected errors.** An `ArgumentError`
  that reaches the error handler outside coverage loading is now an `UnknownError`
  ("An unexpected error occurred: ...", exit `1` in the CLI) instead of a
  `ConfigurationError` or `UsageError` ("Invalid configuration: ..."). User-input
  validation raises `UsageError`/`ConfigurationError` directly and is unaffected.
- **`CoverageCLI::SUBCOMMANDS` moved to `CovLoupe::SUBCOMMANDS`.** The list of valid
  subcommands now lives in its own file so startup option-error handling does not
  need to load the whole CLI. Both constants are internal; for the public list of
  subcommands, see [CLI Usage](docs/user/CLI_USAGE.md#subcommands).
- **Logging defaults and fallback behavior changed.** CLI and MCP sessions now
  log to `stderr` by default, while library usage is quiet by default. The
  previous implicit `./cov_loupe.log` target and `COV-LOUPE-LOG-ERROR.log`
  fallback are removed. Persistent logging requires an explicit file target via
  `--log-file`, `CovLoupe.default_log_file`, or `CovLoupe.active_log_file`; users
  who choose a file target are responsible for cleanup or external rotation.
  Logging failures no longer replace the original MCP tool error.
- **Logging targets are validated during initialization.** Library mode raises
  `CovLoupe::LoggingError` immediately for an unusable target; CLI mode reports a
  warning; and MCP mode returns `isError: true` for every affected tool call. The
  underlying logger remains lazy, so a successful startup probe does not create a
  persistent log file until the first diagnostic is written. The internal
  context is quiet for library callers; CLI and MCP entry points create their
  own mode-specific logging contexts.
- **Stderr log targets are normalized consistently.** Values such as `stderr`,
  `STDERR`, values with surrounding whitespace, and (in the library) the symbol
  `:stderr` now all select the
  standard-error stream instead of being interpreted as file paths.
- **Only `coverage.json` is read, and it must be in the format written by SimpleCov 1.x.** cov-loupe now reads SimpleCov's documented JSON formatter output, which SimpleCov 1.0.0 and later write alongside the HTML report. `.resultset.json`, SimpleCov's internal merge cache, is no longer read.
    - **Old:** `.resultset.json` was the input; SimpleCov was loaded at runtime to merge multi-suite resultsets.
    - **New:** `coverage.json` is the input. It is already merged across suites, so SimpleCov is never loaded. It is discovered at `coverage/coverage.json` under the project root (see below).
    - `simplecov` is no longer a gem dependency (6.x required `>= 0.21`). Instead, `meta.schema_version` in `coverage.json` is checked on load: any 1.x is accepted, and a missing value or another major version raises `Unsupported coverage.json format (meta.schema_version: ...)`, naming the file, the value found, and `meta.simplecov_version` when present. This rejects `coverage.json` files written for SimpleCov 0.x by the separate `simplecov_json_formatter` gem, which have no `schema_version`.
    - Lines marked `"ignored"` by SimpleCov (`:nocov:` regions and `# simplecov:disable` directives) are treated as non-executable, so cov-loupe's percentages match SimpleCov's own report.
    - The not-found message is now `Could not find coverage.json under "<root>"`, and stale-coverage errors label the file `Coverage file - <path>`.
    - Projects that cannot upgrade SimpleCov should stay on cov-loupe 6.x. See [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md).
- **The `resultset` names are replaced by `coverage_file` names.** The `--coverage-file` option (`-c`; see below), the `coverage_file` MCP tool argument, `CoverageModel.new(coverage_file:)`, `#coverage_file_path`, `CoverageReporter.report(coverage_file:)`, `CovLoupe::CoverageFileNotFoundError`, and `Resolvers::CoverageFilePathResolver` are the only spellings. `--resultset`, the `resultset` tool argument, `resultset:` keywords, `#resultset_path`, `ResultsetNotFoundError`, `ResultsetPathResolver`, `ResolverHelpers.find_resultset`, and `AppConfig#resultset` are gone, with no deprecation period. `ResultsetLoader` is replaced by `CoverageJsonLoader`, whose `Result` has `coverage_map` and `timestamp` only.
    - `ResolverHelpers.create_resultset_resolver` and its `candidates:` keyword are removed. Instantiate `CoverageFilePathResolver.new(root:)` directly.
    - Direct callers of `CoverageRepository` and `CoverageJsonLoader` must also update `resultset_path:` to `coverage_file:` and `resolved_coverage_file:` respectively; `CoverageRepository#resultset_path` is now `#resolved_coverage_file`.
    - `CoverageFilePathResolver`, `ResolverHelpers`, `CoverageRepository`, `CoverageJsonLoader`, and `AppConfig` are internal as of 7.0 and may change in any release.
    - See [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md) for the full rename table.
- **Short options `-c` and `-n` reassigned.** The coverage file option is `-c`/`--coverage-file` (6.x: `-r`/`--resultset`), and `--context-lines` is now `-n` (was `-c`).
    - `-r` now fails with `ambiguous option: -r`. An old `-c N` for context lines is parsed as `--coverage-file N` and fails with a not-found error, so update shell aliases, `COV_LOUPE_OPTS`, and MCP server `args`.
    - The CLI not-found tip now reads `Specify a coverage file: cov-loupe -c PATH`.
- **Coverage percentages are truncated, not rounded, to two decimals.** Rounding could
  report incomplete coverage as `100.0` (for example, 99,999 of 100,000 lines), so a
  `percentage >= 100` policy passed with uncovered lines. Every `percentage` in library
  hashes, CLI output, and MCP payloads can now be up to `0.01` lower (2 of 3 lines is
  `66.66`, was `66.67`), so `validate` predicates with thresholds close to the value can change
  result. `CoverageReporter.report` now shows two decimals (was one) so it cannot round
  up to `100.0%` either. See [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#percentages-truncated-not-rounded).
- **Only `coverage/coverage.json` is searched by default.** With no `--coverage-file`, cov-loupe looks only at `coverage/coverage.json` under the project root, where SimpleCov writes it. 6.x tried `.resultset.json`, `coverage/.resultset.json`, and `tmp/.resultset.json` in turn; use `--coverage-file` (`-c`) for any location other than the default.
- **`--output-chars ascii` no longer changes data.** The mode exists for terminals that cannot
  draw fancy table borders, but it used to rewrite all output: accented Latin letters and some
  symbols were transliterated and every other non-ASCII character became `?`, altering file
  paths, source lines and error messages. Now it changes only what cov-loupe draws itself (table
  borders and the covered-line marker), and data is shown exactly as it is. This applies to the
  MCP `output_chars` argument and the library's `output_chars: :ascii` too, and to `default`
  when it picks ASCII mode for a non-UTF-8 terminal. In ASCII mode, successful JSON payloads
  still escape non-ASCII characters as `\uXXXX`; other output is no longer guaranteed to be
  ASCII-only. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#output-chars-ascii-no-longer-changes-data).
- **Source and predicate files are read as UTF-8 in every locale.** They used to be read in
  the locale's encoding, so a file in a non-UTF-8 encoding (such as ISO-8859-1) worked under a
  matching locale. Now source display (`--source`) of such a file shows its non-ASCII bytes
  raw in the table and escaped (such as `\xE9`) in the other text formats, and JSON or YAML
  output fails with "Source file is not valid UTF-8"; a `validate` predicate file in such an
  encoding fails to evaluate if it has non-ASCII characters outside comments, such as in
  string literals. Convert such files to
  UTF-8 (a `# encoding:` magic comment lets a predicate parse, but its non-ASCII strings then
  do not match the UTF-8 coverage data). UTF-8 files, which are Ruby's default, are
  unaffected. See
  [Migrating to v7](docs/user/migrations/MIGRATING_TO_V7.md#source-and-predicate-files-are-read-as-utf-8).

### Other Changes

- **New Test Coverage Analysis prompt.** The
  [Test Coverage Analysis prompt](docs/user/prompts/test-coverage-analysis-prompt.md) has an
  AI agent use cov-loupe to report coverage by logical area (down to individual classes and
  methods), rank gaps by risk, and review test quality. It runs unattended against an
  existing, passing test run, so several agents can run it at once. It replaces the
  Coverage Analysis prompt (`docs/user/prompts/coverage-analysis-prompt.md`), which is
  removed.
- **Non-ASCII paths and source are read correctly under the C locale.** Under `LANG=C`:
    - Fixed: a coverage file with a non-ASCII path didn't load, in the CLI or MCP
      ("Invalid encoding in coverage data").
    - Fixed: a non-ASCII path given on the command line wasn't found ("No coverage entry
      found").
    - Fixed: `list`, `totals`, the per-file commands (`summary`, `uncovered`, `detailed`) and
      the matching MCP tools failed with an unexpected error when a source file contained
      non-ASCII text.
    - Fixed: a `validate` predicate file containing a non-ASCII string literal failed to
      evaluate.
    - Fixed: in a directory with a non-ASCII name, `-R .` and `-c coverage` failed, and
      `--tracked-globs` reported covered non-ASCII files as missing.
    - `coverage.json`, source files and predicate files are now always read as UTF-8, also
      when `Encoding.default_internal` is set. For files in another encoding, see the
      Breaking entry "Source and predicate files are read as UTF-8 in every locale".
    - Under the C locale the `cov-loupe` executable sets `Encoding.default_external` to
      UTF-8, so paths from the file system are UTF-8 too, and it treats CLI arguments that
      arrive as raw bytes as UTF-8 when they are valid UTF-8.
    - The default output character mode is still chosen from the original encoding, so it is
      unchanged (on CRuby, CLI output under `LANG=C` still gets ASCII table borders).
    - One visible change: under `LANG=C` the `inspect`, `pretty_print`, `amazing_print` and
      `puts` formats now show non-ASCII characters as they are instead of escaping them as
      `\uXXXX`.
    - Fixed: when `Encoding.default_internal` was a non-UTF-8 encoding (for example with
      `RUBYOPT=-E:US-ASCII`), the MCP server crashed on a request containing non-ASCII
      characters, or with an encoding such as ISO-8859-1 misread its paths. It now reads and
      writes JSON-RPC as UTF-8 with no transcoding, and writes its stderr log lines the same
      way (under `RUBYOPT=-U` and `LANG=C`, a log line naming a non-ASCII path failed with
      "log writing failed").
    - Fixed: a command-line argument that is not valid text in its encoding, such as a file
      name that is not UTF-8, crashed `OptionParser` with a backtrace (as an option value) or
      reported "An unexpected error occurred" (as a path). It is now rejected with a usage
      error that names the argument, and exit code 2.
    - CLI output still fails if the output stream transcodes to a non-UTF-8 encoding (for
      example `RUBYOPT=-U` under `LANG=C`). Encoding errors outside coverage loading, such as
      this CLI output failure or one in an MCP tool call, are now reported as a text encoding
      error (`CovLoupe::TextEncodingError`) instead of "Invalid encoding in coverage data",
      which is now used only for errors while loading the coverage data.
    - On JRuby, non-ASCII paths under `LANG=C` remain unsupported, because the JVM cannot
      open them in that locale.
    - Library callers must pass non-ASCII paths as UTF-8; see
      [Quick Start](docs/user/LIBRARY_API.md#quick-start).
- **Structured payloads now include `schema_version`.** Every library coverage hash (`list`, `summary_for`, `uncovered_for`, `detailed_for`, `raw_for`, `project_totals`), structured CLI output (all formats except `table`), and MCP tool payload now begins with an integer `schema_version` (currently `1`), separate from `CovLoupe::VERSION` and from SimpleCov's own `schema_version` in `coverage.json`. Draft 2020-12 JSON Schema files for each v1 payload shape ship under `lib/cov_loupe/schemas/v1/` and are resolvable via `CovLoupe::PayloadSchema.schema_path`. Adding a key is a compatible change and does not bump the version; see [Schema Version](docs/user/LIBRARY_API.md#schema-version) for the full compatibility rules.
- **Quieter CLI stderr.** The `CLI parameters` line is now logged only when `--log-file` is a
  file. With the default `stderr` target, a CLI error is printed once, as its user-facing
  message, instead of also appearing as `ERROR` log lines; `--error-mode debug` follows it with
  the full stack trace (also with `--log-file off`; with a log file, stderr gets the first 5 lines
  and the log the full trace). Unknown-subcommand errors now also reach a `--log-file`. Running
  `cov-loupe` with no subcommand now reports an unexpected error the same way as a subcommand
  does, instead of exiting with a raw Ruby backtrace.
- **Custom CLI error handlers see an unexpected error once.** A handler passed to
  `CoverageCLI.new(error_handler:)` now receives an unexpected (non-`CovLoupe::Error`) error
  from a subcommand or the default report once, as the original exception with
  `reraise: false`. Previously it was called twice: first with `reraise: true`, expected to
  raise the converted error, then with that converted error. A handler may provide
  `convert_standard_error` to control the conversion. As before, the handler is called for
  every error the CLI reports except invalid options, whatever the log target. `CoverageCLI` and custom error handlers are internal as
  of 7.0; see [Public API and Versioning](docs/user/LIBRARY_API.md#public-api-and-versioning).
- **Misplaced global option hints keep option values.** `cov-loupe totals --format json` now
  suggests `cov-loupe --format json totals` (previously `--format totals`). The suggested
  command keeps options given before the subcommand and quotes arguments that need it.
- **Improved guidance for misplaced short global options.** `-e`/`--error-mode` and `-C`/`--color` used after a subcommand (for example `list -e debug`) now get the "must come BEFORE the subcommand" message instead of a generic "Unexpected argument(s)" error; previously only their long forms were recognized.
- **Fixed `uncovered` and `detailed` crashing on files with no coverable lines.** Their text output raised `TypeError` when a file's coverage percentage was `nil` (for example, a file containing only comments); it now shows `n/a`, as `summary` and `totals` already did. `detailed` and `uncovered` print `No coverable lines.` for such files. The `project_validate` tool description and the code examples in the README, docs and `examples/` now handle `nil` percentages, and the Library API docs, the MCP integration docs and the descriptions of every MCP tool that returns a `percentage` show it as nullable. In the `validate` predicate examples, per-file checks skip files with no coverable lines, and project-total checks treat a `nil` total (nothing measurable, including when every file is stale) as failing.
- **Fixed the MCP server ignoring `--error-mode`.** Tools always used `log` unless a call passed `error_mode`, so starting the server with `--error-mode off` still logged errors and `--error-mode debug` logged no backtraces. A call without `error_mode` now uses the server's mode, and the tools' input schemas no longer advertise `log` as the default. Likewise, they no longer advertise static defaults for `root`, `raise_on_stale`, and `output_chars`, which come from the server's `--root`, `--raise-on-stale`, and `--output-chars`.
- **Fixed misaligned source output without color.** With `-C false` (or when stdout is not a terminal), `--source` rows were one column to the right of the header.
- **The gem now includes `docs/QUICKSTART.md`**, which the README links to.
- **Fixed the stale-coverage hint in `list` warnings.** The "files excluded" and "rows skipped" warnings told you to run with `--raise-on-stale`, which fails without a value; they now say `--raise-on-stale true`.
- **Fixed project-level stale-coverage messages.** `CoverageDataProjectStaleError` (raised by `list`/`totals` with `--raise-on-stale true`) reported its class name instead of "Coverage data appears stale for project", and each file list was run together on one line; files are now listed one per line.
- **Fixed the ambiguous `--coverage-file` hint.** When a relative path resolved under both the current directory and the project root, the error suggested `./`, which does not disambiguate; it now suggests an absolute path. The duplicate-path error also gained a missing space between its sentences.
- **`totals` now warns about missing coverage timestamps in every format.** With `-f json` and the other structured formats it reported `timestamp_status: "missing"` but omitted the stderr warning that `list` prints; it now prints it, as the table format already did.
- **Valid-value hints for every enumerated option.** An invalid `--format`/`-f` or `--output-chars`/`-O` value, or an invalid `-e` (short for `--error-mode`), now gets the "Valid values for ..." hint that `--source`, `--sort-order`, and `--error-mode` already got.
- **The MCP `help` and `version` tools describe the common arguments.** `help` now lists `error_mode`/`output_chars` among every tool's inputs, and the `version` tool no longer says it takes no arguments.
- **Fixed `CoverageReporter.report` with an absolute `SimpleCov.coverage_dir`.** The default coverage location joined the directory onto `SimpleCov.root` even when it was absolute; it is now expanded against the root, as SimpleCov does. An explicit `root:` now also sets where that directory is looked for; it used to be looked for under `SimpleCov.root`.
- **Documentation links work in the installed gem and on GitHub.** Links now point to real files (`README.md`, `LICENSE`, `examples/*/README.md`, ...) rather than to the documentation site's wrapper pages, and the gem now includes the developer docs (`docs/dev/`) they link to. The gem no longer includes `AGENTS.md` or `CLAUDE.md`, which are instructions for agents working in the repository.
- **Fixed duplicate missing tracked files.** A file matched by more than one `--tracked-globs` pattern (for example `lib/**/*.rb` and `lib/*.rb`) was listed twice in `missing_tracked_files` and counted twice in the `totals` `missing_from_coverage` count; it is now listed and counted once.
- **Fixed the `--tracked-globs` help text.** It now points to SimpleCov's `cover` globs; `track_files` is deprecated in SimpleCov 1.x.
- **Fixed `NoMethodError` message rewriting on Ruby 3.4+.** Ruby 3.4 quotes the method name in `NoMethodError#message` as `'name'` instead of the pre-3.4 `` `name' ``, so the friendly "missing method '...' on ..." rewrite silently failed to apply on 3.4+. Both quote styles are now recognized.

## v6.1.0

- In gemspec, change mcp gem's constraints from `'>= 0.15', '< 1.0'` to `'>= 0.15', '< 2.0'`

## v6.0.0

### Breaking

- **Stdout logging is no longer permitted.** The `--log-file` / `-l` option no longer accepts `stdout` in any mode (CLI, MCP, or library). Logs are diagnostics and must not corrupt command output on `stdout` or the MCP JSON-RPC protocol stream.
    - **Old:** `--log-file stdout` was allowed in CLI mode and rejected only in MCP mode.
    - **New:** `--log-file stdout` raises a `ConfigurationError` during normal configuration validation. Use `--log-file stderr`, a file path, or `:off` to disable logging.
    - See [Migrating to v6](docs/user/migrations/MIGRATING_TO_V6.md) for details.
- **`--format` short codes and long names normalized.** Each format now has exactly one canonical short code and one canonical long name; noncanonical aliases (`pretty-json`, `awesome_print`, `ap`) are no longer accepted. New formats `inspect`, `puts`, and `pretty_print` were added.
    - **Old:** `p`/`pretty_json`/`pretty-json` meant multi-line, indented JSON. `a`/`amazing_print`/`awesome_print`/`ap` meant AmazingPrint. `J` was unassigned.
    - **New:** `p` means `puts` (Ruby `Kernel#puts` output). `J` means `pretty_json` (multi-line, indented JSON). `P` means `pretty_print` (Ruby stdlib `PP.pp` output). `i` means `inspect` (Ruby `#inspect` output). `a`/`amazing_print` is unchanged; `awesome_print`/`ap` are no longer accepted.
    - Canonical formats: `a`/`amazing_print`, `i`/`inspect`, `j`/`json`, `J`/`pretty_json`, `p`/`puts`, `P`/`pretty_print`, `t`/`table`, `y`/`yaml`.
    - See [Migrating to v6](docs/user/migrations/MIGRATING_TO_V6.md) for details.
- **MCP tool-call failures now consistently return `isError: true`.** Both argument-validation failures (missing required arguments or invalid enums) and tool-execution failures (bad paths, invalid predicates, stale coverage, etc.) return a `tools/call` result with `isError: true`.
    - Previous guidance described validation failures as top-level JSON-RPC errors; execution failures required callers to parse `"Error: ..."` text from an otherwise successful result.
    - Protocol- and dispatch-level failures such as unknown tools remain JSON-RPC errors, distinct from tool-call errors.
    - The minimum `mcp` dependency is now 0.15. Applications pinned to an older `mcp` version must upgrade before installing cov-loupe v6.

## v5.0.1.pre
- Extract shared RuboCop defaults into `.rubocop-shared.yml` and slim `.rubocop.yml` down to cov-loupe-specific overrides, making lint configuration easier to maintain across related projects.
- Align the codebase and spec suite with the updated RuboCop rules, including removal of the project-specific line-length override and the corresponding style-only cleanup in Ruby sources and tests.
- Expand `AGENTS.md` with Ruby-specific contributor guidance: inspect core project config files before editing, prefer `bundle exec` and binstubs, and run the smallest relevant test first.

## v5.0.0 (Breaking)
- **MCP tool names renamed** to encode scope: file-scope tools are prefixed with `file_` (`file_coverage_summary`, `file_coverage_detailed`, `file_coverage_raw`, `file_uncovered_lines`); project-scope tools are prefixed with `project_` (`project_coverage`, `project_coverage_totals`, `project_validate`). Table output is available through `project_coverage` with `format: "table"`. `help_tool` and `version_tool` drop the `_tool` suffix and become `help` and `version`.

- **Removed `version` subcommand**: `cov-loupe version` no longer exists. Use `cov-loupe -v` or `cov-loupe --version` instead.
- **Simplified `--version` output**: `-v`/`--version` now prints only the bare version string (e.g. `5.0.0`) and exits, instead of displaying a formatted table with `Gem Root` and `Documentation` fields. JSON format is no longer supported for version output.
- Add `-s none` / `--source none` option to disable source code display (previously enabled via `-s full` or `-s uncovered`).
- **`--resource NAME` renamed to `--path-for NAME`** (`-p NAME`); `--resource` is no longer accepted. The names are still `repo`, `docs`, and `docs-local`.
  - Expose canonical resources in MCP `help` under the `resources` key (alongside `tools`).
  - Share resource values from one source of truth (`CovLoupe::Resources::RESOURCE_MAP`) used by:
      - CLI `--path-for`
      - CLI help banner URLs
      - MCP `help`
      - MCP server startup instructions
- **Single-letter abbreviations for CLI subcommands** (added in 4.1.0, which had no release notes): All CLI subcommands can be abbreviated to their first letter. For example, `cov-loupe l` for `list`, `cov-loupe s` for `summary`, `cov-loupe r` for `raw`, `cov-loupe u` for `uncovered`, `cov-loupe d` for `detailed`, `cov-loupe t` for `totals`, `cov-loupe v` for `validate`.
- **Totals key renamed**: The `lines.percent_covered` key in project totals (`project_coverage_totals`, the `totals` subcommand, and `CoverageModel#project_totals`) has been renamed to `percentage`, matching the per-file summaries. Update any code or scripts that read `percent_covered` to use `percentage` instead.
- Make pass/fail symbols in source code display more prominent, change circle to X
- Fix `validate -i` parsing in the top-level argument parser so inline validate code is handled correctly.

## v4.0.0 (Breaking)

- **Removed Branch Coverage Support**: Removed logic that synthesized line coverage from branch-only coverage data. This feature was complex and rarely used. Users should use standard line coverage configuration in SimpleCov.
    - Removed `docs/dev/BRANCH_ONLY_COVERAGE.md`.
- **⚠️ MCP mode now requires `-m/--mode mcp` flag**: Automatic mode detection has been removed. MCP users **must** update their MCP server configuration to include `-m mcp` or `--mode mcp` or cov-loupe will run in CLI mode, print a report, and exit. See migration guide for setup commands.
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
- **Deleted files now raise `FileNotFoundError`**: With `raise_on_stale` enabled, querying a file that was deleted after coverage was generated now raises `FileNotFoundError`, as the API documentation promised, instead of `CoverageDataStaleError`. With `raise_on_stale` off (the default), the stale coverage data is still returned.
    - **Old**: `CoverageModel.new(raise_on_stale: true).summary_for('deleted_file.rb')` raised `CovLoupe::CoverageDataStaleError`
    - **New**: it raises `CovLoupe::FileNotFoundError`
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
- **`--tracked-globs` defaults to an explicit empty array**: The CLI default is now `[]` instead of `nil`, and the Ruby API (`CoverageModel`) also defaults `tracked_globs:` to `[]`. Both behave the same as before: all files in the resultset are shown and none are flagged as missing. (A `lib/**/*.rb,app/**/*.rb,src/**/*.rb` default existed briefly during v4 development but was never released.)
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

- **Changelog:** [RELEASE_NOTES.md](RELEASE_NOTES.md)
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
