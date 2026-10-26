# Test Coverage Analysis by Logical Area Prompt

[Back to main README](../../../README.md)

Give this prompt to an AI coding agent from the root of your Ruby project. It
uses cov-loupe to produce a report of line coverage organized by the logical
parts of your system, down to individual classes and methods, and ranks the
gaps by risk. It never asks for input, so it also works headless (e.g.
`claude -p`, `codex exec`, CI).

**Requirement:** run your full test suite (every suite that feeds SimpleCov)
first, make sure it passes, and don't change source or test files until the
analysis finishes. The prompt does not run tests; it reads the existing
`coverage.json` and refuses to start if that file looks out of date. This lets
several agents run it concurrently against the same coverage data.

---

### Unattended Operation

This prompt never asks the user anything, so it runs the same interactively or
headless. Never stop to wait for input: when a precondition fails, stop with an
error message instead. The invocation may name a different report location
(e.g. "write the report to `tmp/reports`") or coverage file location.

### Preconditions

Before you begin the analysis:

1. If your current working directory is not the project root (the output of
   `git rev-parse --show-toplevel`), stop with an error that states your
   current working directory and the expected root. Do not run the analysis.
2. Always open the report by citing the most recent git commit at the time you
   begin writing.
3. If `git status` shows uncommitted changes, include them in the analysis:
   analyze the working tree as it is, and list the `git status` details
   immediately after the commit citation.
4. Analyze the files git would consider part of the project: tracked files
   plus new files not yet added, excluding anything git ignores
   (`git ls-files --cached --others --exclude-standard`). Mark the untracked
   files in the `git status` details.

----

- You are a senior engineer assessing the test suite of this project.
- Your task is to produce a report of line coverage **organized by the logical
  parts of the system**, not just a per-file list, and to judge where the gaps
  actually matter.
- Get every coverage number from cov-loupe. Do not read `coverage.json`
  directly, and do not estimate coverage by reading tests. Aggregating
  cov-loupe's per-line output into area totals is expected (see Step 4).
- Prefer the cov-loupe MCP server. If it is unavailable, use the CLI
  (`cov-loupe`, or `bundle exec cov-loupe` if it is in the Gemfile; run
  `cov-loupe --help` for usage), adding `-m cli -fJ` for JSON output. Say in
  the report which one you used.
- Use source and test files only to define the logical areas and to judge the
  importance of uncovered code.
- Do not run the test suite, and do not modify source files, test files, or
  coverage output. Other agents may be running this analysis concurrently
  against the same data. This is a read-only analysis; the only file you
  write is the report.
- Before recommending tests for uncovered code, check whether it is
  intentionally excluded or untested: SimpleCov filters and `# :nocov:`
  markers, and any project documentation or code comments explaining why.

## Step 1: Verify the coverage data is current

The user must run the full, passing test suite before this analysis. Verify
what you can, and if any check below fails, stop with an error that names the
failed check and tells the user to rerun the full suite. Do not write a report.

1. Find the SimpleCov configuration (`.simplecov`, `spec/spec_helper.rb`,
   `test/test_helper.rb`, or wherever the project starts SimpleCov) and the
   coverage file (`coverage/coverage.json` unless the configuration or the
   invocation says otherwise). The file must exist and be written by
   SimpleCov 1.x.
2. Run the project totals with the tracked globs from Step 2
   (`project_coverage_totals` / `cov-loupe -m cli -fJ -g '<globs>' totals`)
   and the file list with the same globs (`project_coverage` /
   `cov-loupe -m cli -fJ -g '<globs>' list`). `timestamp_status` must be `ok`,
   and `newer_files`, `deleted_files`, `length_mismatch_files`,
   `unreadable_files`, and `skipped_files` must all be empty. These show
   whether source files changed after the run.
3. No test, fixture, or configuration file may be newer than the coverage
   file, since cov-loupe checks only source files. For example:
   `find spec test features Gemfile.lock .rspec .simplecov -newer coverage/coverage.json`
   (adjusted to the paths that exist). Include directories in the search,
   not just files, so that deleted test files show up too.
4. If the project records test results, they must show no failures: for
   RSpec, the file named by `example_status_persistence_file_path`
   (commonly `.rspec_status`) must have no `failed` entries.

These checks cannot prove that the last run was the complete suite. Say in
the report that the analysis relies on the user's assurance that it was.

`missing_tracked_files` (tracked files the suite never loaded) is not a
staleness failure; it is a finding for Step 2.

## Step 2: Establish the project baseline

1. Get overall totals with no globs, then with tracked globs matching the
   code SimpleCov is meant to measure (from its `track_files` and filter
   settings; typically `lib/**/*.rb`, or `app/**/*.rb,lib/**/*.rb` for Rails).
   Passing `tracked_globs` makes cov-loupe report tracked files that have
   **no** coverage data at all (`missing_tracked_files`, `without_coverage`);
   these are files never loaded by the suite and are often the biggest real
   gap.
2. Get the full file list as JSON, sorted ascending (worst first).
3. Note what the numbers cover: cov-loupe reports **line** coverage only.
   If SimpleCov also collects branch coverage, say that branch coverage is out
   of scope for this report.

## Step 3: Identify the logical areas

Before computing any rollups, decide how to carve up the code. The goal is the
most precise, targeted analysis, so draw boundaries by what the code does, not
by where it lives. File and directory boundaries are not area boundaries: one
file may hold a class or module with a critical mission next to code that
matters little, and those belong in different areas. This takes more reading
and more tokens than a file-level rollup; that is the point.

1. Read the code to understand its structure: entry points, `require` and
   autoload structure, namespaces, classes, modules, and methods, and how
   responsibilities flow between them. Identify the kind of project (Rails
   app, gem, CLI tool, service) and its conventions.
2. Define **logical areas at whatever granularity is meaningful**. An area is
   a set of code units (classes, modules, methods, or line ranges) wherever
   they live. It can be:
   - a broad grouping spanning several directories (e.g. "everything in the
     checkout flow", "the public API"),
   - a single namespace or class,
   - a single method or a few methods within a class (e.g. the price
     calculation inside an order model, or the argument parsing in a CLI
     command),
   - or a cross-cutting concern spanning many places (e.g. authorization,
     error handling, input validation).
3. Arrange the areas in a hierarchy where that helps (a broad area containing
   narrower ones), and nest as deep as it is useful. Cross-cutting areas may
   overlap others; say so where they do.
4. Record each area's definition precisely as file paths with line ranges, and
   name the classes, modules, or methods those ranges cover so a reader can
   follow them. When an area is made of whole files, a glob is a fine
   shorthand.
5. Make sure at least one level of the hierarchy is a **complete partition**:
   every coverable line in the source files under analysis belongs to exactly
   one area at that level, with an explicit "Other" area for code that fits
   nowhere. This level is what the totals are reconciled against.
6. Give each area a **criticality** judgment with a short reason. Treat it as a
   continuum, not a fixed set of buckets: place each area relative to the
   others and explain what drives the placement. Weigh user-visible behavior,
   data correctness and integrity, money and security (authentication,
   authorization, code evaluation, file system access), error paths, public
   API, and how often the code runs. Use the framework's usual danger spots as
   prompts, not as fixed categories: in a Rails app, validations, callbacks,
   and scopes that guard data; authorization in controllers; background-job
   retries and failure handling; mailers; CSRF and parameter filtering. In
   other projects, look at domain rules and calculations, state transitions,
   external API clients, file I/O and parsing, serialization, and concurrency.

## Step 4: Compute coverage per area

1. For each file touched by an area, get per-line data with
   `file_coverage_detailed` / `cov-loupe -m cli -fJ detailed <path>`. Each row
   gives a line number, its hit count, and whether it is covered; lines that
   are not coverable (comments, blank lines, `end`) do not appear.
2. For each area, sum the covered and coverable lines that fall in its line
   ranges, and compute the percentage. Also record the number of code units
   in the area and its weakest units (e.g. the least-covered methods).
3. Get a broader area's numbers by summing its children's line counts, never
   by averaging child percentages.
4. For an area made of whole files, cross-check your sums against
   `project_coverage_totals` with `tracked_globs` /
   `cov-loupe -m cli -fJ -g '<globs>' totals`; they must match exactly.
5. Confirm that the line totals for the partition level from Step 3 add up to
   the project's covered and total lines for the same overall globs. If they
   don't, find the overlap or orphaned lines and fix the map; state any
   remaining discrepancy.
6. Keep the aggregation mechanical and reproducible. If you write a helper
   script to sum the per-line rows, put it in a temporary directory of your
   own outside the project (e.g. from `mktemp -d`, so concurrent agents don't
   collide), feed it cov-loupe output only, and include it in the appendix.

## Step 5: Examine the gaps

Decide for yourself which files and areas deserve a close look. Do not apply a
fixed percentage cutoff: weigh each area's coverage against its criticality,
so a critical area at a high percentage can still warrant scrutiny while a
low-stakes area at a lower percentage may not. Always include every tracked
file with no coverage data. State the reasoning behind your selection in the
report.

For each selected file or area:

1. Get the uncovered lines (`file_uncovered_lines` /
   `cov-loupe -m cli -fJ uncovered <path>`); use `file_coverage_detailed` or
   `cov-loupe -m cli -s uncovered -n 2 uncovered <path>` to see the source in
   context.
2. Characterize each cluster of uncovered lines: error/rescue path, edge-case
   branch, defensive guard, platform-specific code, dead code, debug/logging
   code, or core logic.
3. Find the tests for that code, following the project's conventions (e.g.
   `spec/` mirroring `lib/` or `app/`, or `test/`). Note whether the gap is
   "no tests at all", "tests exist but miss these paths", or "covered only
   indirectly by integration tests".
4. Judge the **risk** of each gap: what goes wrong for a user if this code is
   broken and no test notices? Be concrete.
5. Judge, separately from risk, how **hard the gap is to test**: dependencies
   to set up, I/O, external services, time, concurrency, or missing seams
   (code that can't be exercised without refactoring).
6. Flag likely dead code separately: it should be deleted, not tested.

Do not pad the report: a high percentage with an untested critical error path
is worth more attention than modest coverage of formatting helpers.

## Step 6: Look beyond line percentages

Briefly assess, per major area, using the tests themselves:

- Whether coverage comes from focused unit tests or only from broad
  integration/end-to-end tests (high coverage via integration alone can hide
  weak assertions).
- Whether tests assert on behavior or merely execute code (spot-check a few
  tests per area; cite them).
- Consistency across entry points: behavior reachable through more than one
  interface (e.g. web UI and API, CLI and library) should be tested through
  each.
- Testing anti-patterns. Report only those you actually observe, such as:
  over-mocking that makes tests brittle or hides integration bugs;
  near-duplicate test code that should use shared examples, helpers, or
  iteration over input arrays; untested error handling and failure
  scenarios; missing integration tests for critical user flows; untested
  authorization logic; controller tests where request specs would serve
  better (Rails); missing tests for jobs, mailers, external integrations,
  CLI argument parsing, or data transformation pipelines.
- Testing infrastructure problems: inadequate fixtures or factories, missing
  helpers, or code structure that makes tests hard to write.
- Well-tested areas: where coverage and test quality are both strong, and
  the testing patterns there that are worth repeating elsewhere.

Keep this qualitative and evidence-based; cite test files and line numbers.

## Report

Write your analysis in the project root (or in the directory the invocation
names) as a Markdown file whose name is:
- today's date in UTC `%Y-%m-%d-%H-%M` format +
- '-test-coverage-analysis-' +
- your name (e.g. 'codex', 'claude', 'gemini') +
- the `.md` extension.

If a file with that name already exists (another agent finished in the same
minute), append `-2`, `-3`, and so on before the extension. Never overwrite an
existing report.

The file should have the following structure:

---

### Executive Summary
- Commit cited, cov-loupe interface used (MCP or CLI), coverage file
  timestamp, and the results of the Step 1 checks.
- Overall line coverage (with and without tracked globs).
- The best- and worst-covered areas, and the top risk areas.
- A **one-line verdict** (e.g. *"Strong domain coverage; payment error
  handling is the main gap"*).

### Area Map
The hierarchy of logical areas from Step 3, showing for each area its parent,
its definition (file paths with line ranges and the code units they cover, or
globs for whole files), and criticality with reason. Mark the partition level
used for reconciliation and any overlapping cross-cutting areas. Explain why
you carved the code this way.

### Coverage by Area
One table per hierarchy level that is worth showing, each sorted ascending by
percentage:

| Area | Criticality | Code units | Covered | Total | % | Weakest unit (%) |
|------|-------------|------------|---------|-------|---|------------------|

List tracked files with no coverage data separately, with the areas they
belong to.

Follow with a short interpretation of each area that stands out, positively or
negatively, relative to its criticality.

### Gap Analysis
State how you chose what to examine. Then, for each gap from Step 5, grouped by
area and ordered by risk:
- File and uncovered line numbers (as reported by cov-loupe).
- What the code does and the gap's category.
- Test status (none / partial / indirect only).
- Risk, with a concrete failure scenario.
- Difficulty to test, with what makes it hard.
- Recommendation: test to add (describe the scenario, not the code), code to
  delete, or "acceptable as is" with the reason.

### Well-Tested Areas
Areas where coverage and test quality are both strong, and the patterns
worth repeating, with citations.

### Test Quality Observations
The remaining findings from Step 6 (unit vs. integration balance, assertion
strength, entry-point consistency, anti-patterns, infrastructure), with
citations.

### Data Caveats
Reliance on the user's assurance that the last run was the complete, passing
suite; tracked files missing from the coverage data; branch coverage being out
of scope; ambiguous line assignments at area boundaries; anything else that
limits confidence in the numbers.

### Prioritized Recommendations
A numbered list, highest value first, weighing risk reduced against
difficulty. Include testing-infrastructure fixes where they unblock other
recommendations. For each: the area, the effort (S/M/L), the expected
coverage or risk improvement, and a ready-to-use prompt the user can give an
AI assistant to implement it.

### Appendix: Commands Run
Every cov-loupe call (MCP tool name and arguments, or CLI command) and
freshness check used to produce the numbers, plus any aggregation script, so the
report can be reproduced.

---

End your final message with the report's path and the one-line verdict, or,
if you stopped early, with the error. A headless caller can then find the
outcome without parsing the rest of your output.
