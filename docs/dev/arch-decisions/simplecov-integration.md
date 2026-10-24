# SimpleCov Integration

[Back to main README](../../../README.md)

This document describes how cov-loupe integrates with SimpleCov: which of SimpleCov's output files it reads, and why it validates that file's format on load instead of declaring SimpleCov as a dependency.

## Input Format: `coverage.json` Only

### Status

**Accepted** (v7.0.0) – cov-loupe reads SimpleCov's `coverage.json` and nothing else. Support for `.resultset.json` was removed.

### Context

SimpleCov writes two JSON files:

- **`.resultset.json`** is SimpleCov's internal merge cache, keyed by test suite name. Its shape is undocumented and carries no compatibility promise. Before SimpleCov 1.0.0 it was the only machine-readable output, so cov-loupe read it, merged suites with SimpleCov's own combiner (which required SimpleCov at runtime), and adapted to its historical variations (raw line arrays vs `{ "lines" => [...] }` entries, `timestamp` vs `created_at`).
- **`coverage.json`** is the output of SimpleCov's JSON formatter. From SimpleCov 1.0.0 on it is described by a versioned JSON schema in the SimpleCov repository, and the default HTML formatter writes it alongside the report, so nearly every 1.x project has one after a test run. It contains a single already-merged coverage map with project-relative file keys, an ISO 8601 `meta.timestamp`, and `"ignored"` markers for lines excluded by `:nocov:` regions.

cov-loupe 6.x and earlier read only `.resultset.json`. That meant a loader that adapted to the file's historical shape variations, a three-entry candidate list whose ordering had to be documented, `resultset` naming throughout the public API, and a runtime SimpleCov load to merge multi-suite resultsets.

### Decision

Read only `coverage.json` and require the format written by SimpleCov 1.x.

Consequences:

- One loader (`CoverageJsonLoader`) with no format detection and no suite merging.
- Discovery checks a single path, `coverage/coverage.json` under the project root, with no cross-format precedence to explain. Other locations are reached with `--coverage-file`.
- The public API uses `coverage_file` names only; the `resultset` names and their deprecation shims are gone.
- Users on SimpleCov 0.x must upgrade SimpleCov, or stay on cov-loupe 6.x. See [Migrating to v7](../../user/migrations/MIGRATING_TO_V7.md).

### `coverage.json` Format

The parts cov-loupe reads:

```json
{
  "meta": {
    "schema_version": "1.0",
    "simplecov_version": "1.0.3",
    "command_name": "RSpec",
    "timestamp": "2026-07-01T12:00:00.000+00:00"
  },
  "coverage": {
    "lib/foo.rb": {
      "lines": [null, 1, 3, 0, "ignored", 5]
    }
  }
}
```

- `coverage` maps project-relative file paths to per-file data; `CoverageRepository` expands the keys against the project root.
- `lines` is an array where index N describes source line N+1: `null` = not executable, `0` = not covered, `>0` = hit count, `"ignored"` = excluded via `:nocov:` or `simplecov:disable` (mapped to `null` on load so excluded lines stay out of the counts).
- `meta.schema_version` is the version of the `coverage.json` format, not of the SimpleCov gem. It is required: any 1.x is accepted, and a missing value or another major version is rejected on load (see [No SimpleCov Gem Dependency](#no-simplecov-gem-dependency)). `meta.simplecov_version` is optional and only quoted in that error.
- `meta.timestamp` is when the coverage was collected, normalized to epoch seconds for staleness checks. A missing or unparseable value becomes 0, which disables time-based checks.

Other keys (`$schema`, `total`, `groups`, `errors`, `branches`, `methods`, source text) are ignored.

## No SimpleCov Gem Dependency

### Status

**Accepted** (v7.0.0) – SimpleCov is not a dependency of cov-loupe. The input format is validated on load instead.

### Context

cov-loupe only reads a file SimpleCov wrote earlier, so it has no functional need to load SimpleCov. Earlier versions loaded it lazily to merge multi-suite resultsets; `coverage.json` is already merged, so that is gone.

A gem dependency (`>= 1.0`) was considered as a guard against SimpleCov 0.x, which writes only `.resultset.json` by default (the separate `simplecov_json_formatter` gem adds a `coverage.json` without `schema_version`, which the format check rejects). It was dropped because it constrains the SimpleCov installed alongside cov-loupe, not the one that wrote the file being read (cov-loupe may be installed globally or inspect another project), and it forces SimpleCov into bundles that only inspect coverage. Checking the file itself validates what cov-loupe actually consumes.

### Decision

`CoverageJsonLoader` checks `meta.schema_version`, SimpleCov's output format version (e.g. `"1.0"`). Any 1.x is accepted. A missing value or another major version raises `CoverageDataError` naming the file, the value found, and `meta.simplecov_version` when present.

### Consequences

- No SimpleCov code runs inside cov-loupe; JSON parsing uses the standard library.
- Installing cov-loupe does not install SimpleCov or constrain a project's SimpleCov version.
- An incompatible file fails at load time with an actionable message instead of being misread.
- cov-loupe's own test suite declares `simplecov` (`>= 1.0, < 2.0`) in the `Gemfile`. The `compat` CI job runs it at `1.0.0` and at the newest release (left unpinned, so Bundler resolves the current version) so a SimpleCov point release that changes `coverage.json` fails there rather than for users.

### References

- JSON parsing and format check: `lib/cov_loupe/loaders/coverage_json_loader.rb` (`CoverageJsonLoader.load`)
- Coverage file discovery: `lib/cov_loupe/resolvers/coverage_file_path_resolver.rb` (`CoverageFilePathResolver::DEFAULT_COVERAGE_FILE`)
- Coverage calculations: `lib/cov_loupe/coverage/coverage_calculator.rb` (`CoverageCalculator.summary`, `.uncovered`, `.detailed`)
- SimpleCov `coverage.json` schema: https://github.com/simplecov-ruby/simplecov/tree/main/schemas
- Development usage: `spec/spec_helper.rb` runs SimpleCov on cov-loupe's own suite, and `CoverageReporter` reads the resulting `coverage.json`
