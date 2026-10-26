# Test Coverage Analysis Prompt

### Unattended Operation

This prompt never asks the user anything, so it runs the same interactively or
headless (e.g. `claude -p`, `codex exec`, CI). Never stop to wait for input:
when a precondition fails, stop with an error message instead. The invocation
may name a different report location (e.g. "write the report to
`tmp/reports`").

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
4. Limit the analysis strictly to git-tracked files. New source files that are
   not yet tracked are excluded; list them after the `git status` details.

----

- You are a senior engineer assessing the test suite of this project.
- Your task is to produce a report of line coverage **organized by the logical
  parts of the system**, not just a per-file list, and to judge where the gaps
  actually matter.
- Get every coverage number from cov-loupe. Do not read
  `coverage/coverage.json` directly, and do not estimate coverage by reading
  specs. Aggregating cov-loupe's per-line output into area totals is expected
  (see Step 4).
  Prefer the cov-loupe MCP server; if it is unavailable, use `cov-loupe` in CLI
  mode (`bundle exec exe/cov-loupe -h` in this repo). Say in the report which
  one you used.
- Use source and spec files only to define the logical areas and to judge the
  importance of uncovered code.
- Do not modify source or spec files. This is a read-only analysis; the only
  file you write is the report.
- Consult `dev/prompts/guidelines/ai-code-evaluator-guidelines.md` and
  `docs/dev/arch-decisions` before recommending tests for code that is
  intentionally untested or excluded.

## Step 1: Produce fresh coverage data

1. Run the full suite (`bundle exec rspec`) to regenerate
   `coverage/coverage.json`. Record the pass/fail/pending counts.
2. If the suite fails, stop with an error that lists the failing examples. Do
   not run the analysis or write a report: a failing suite makes coverage
   numbers misleading.
3. If you cannot run the suite, use the existing coverage file, say so
   prominently, and report its timestamp.
4. Check staleness before trusting any number. Run the project totals
   (`project_coverage_totals` / `cov-loupe -f J totals`) and confirm
   `timestamp_status` is `ok` and that the stale counts are zero. If any
   `newer_files`, `deleted_files`, `length_mismatch_files`,
   `unreadable_files`, `skipped_files`, or `missing_tracked_files` appear in
   `project_coverage` / `cov-loupe -f J list`, list them in the report and
   exclude them from percentages rather than silently counting them.

## Step 2: Establish the project baseline

1. Get overall totals with no globs, then with the project's real tracked
   globs (for this repo, read the `SimpleCov.start` block in
   `spec/spec_helper.rb`; typically `lib/**/*.rb`). Passing `tracked_globs`
   makes cov-loupe report tracked files that have **no** coverage data at all
   (`missing_tracked_files`, `without_coverage`); these are files never loaded
   by the suite and are often the biggest real gap.
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

1. Read the code to understand its structure: entry points and `require`
   graphs (e.g. `lib/cov_loupe.rb`, `lib/cov_loupe/loaders/`), namespaces,
   classes, modules, and methods, and how responsibilities flow between them.
2. Define **logical areas at whatever granularity is meaningful**. An area is
   a set of code units (classes, modules, methods, or line ranges) wherever
   they live. It can be:
   - a broad grouping spanning several directories (e.g. "everything the CLI
     path uses"),
   - a single namespace or class,
   - a single method or a few methods within a class (e.g. the staleness
     checks inside the coverage model, or the argument validation in the MCP
     tools),
   - or a cross-cutting concern spanning many places (e.g. error handling,
     path resolution, output formatting across CLI and MCP).
3. Arrange the areas in a hierarchy where that helps (a broad area containing
   narrower ones), and nest as deep as it is useful. Cross-cutting areas may
   overlap others; say so where they do.
4. Record each area's definition precisely as file paths with line ranges, and
   name the classes, modules, or methods those ranges cover so a reader can
   follow them. When an area is made of whole files, a glob is a fine
   shorthand.
5. Make sure at least one level of the hierarchy is a **complete partition**:
   every coverable line in the tracked source files belongs to exactly one area
   at that level, with an explicit "Other" area for code that fits nowhere.
   This level is what the totals are reconciled against.
6. Give each area a **criticality** judgment with a short reason. Treat it as a
   continuum, not a fixed set of buckets: place each area relative to the
   others and explain what drives the placement. Weigh user-visible behavior,
   data correctness, security boundaries (e.g. code evaluation, file system
   access), error paths, public API (`@api public` YARD tags), and how often
   the code runs.

## Step 4: Compute coverage per area

1. For each file touched by an area, get per-line data with
   `file_coverage_detailed` / `cov-loupe -f J detailed <path>`. Each row gives
   a line number, its hit count, and whether it is covered; lines that are not
   coverable (comments, blank lines, `end`) do not appear.
2. For each area, sum the covered and coverable lines that fall in its line
   ranges, and compute the percentage. Also record the number of code units
   in the area and its weakest units (e.g. the least-covered methods).
3. Get a broader area's numbers by summing its children's line counts, never
   by averaging child percentages.
4. For an area made of whole files, cross-check your sums against
   `project_coverage_totals` with `tracked_globs` /
   `cov-loupe -f J -g '<globs>' totals`; they must match exactly.
5. Confirm that the line totals for the partition level from Step 3 add up to
   the project's covered and total lines for the same overall globs. If they
   don't, find the overlap or orphaned lines and fix the map; state any
   remaining discrepancy.
6. Keep the aggregation mechanical and reproducible. If you write a helper
   script to sum the per-line rows, put it in your scratch space (not the
   repo), feed it cov-loupe output only, and include it in the appendix.

## Step 5: Examine the gaps

Decide for yourself which files and areas deserve a close look. Do not apply a
fixed percentage cutoff: weigh each area's coverage against its criticality,
so a critical area at a high percentage can still warrant scrutiny while a
low-stakes area at a lower percentage may not. Always include every tracked
file with no coverage data. State the reasoning behind your selection in the
report.

For each selected file or area:

1. Get the uncovered lines (`file_uncovered_lines` / `cov-loupe -f J
   uncovered <path>`); use `file_coverage_detailed` or
   `cov-loupe -s uncovered -n 2 uncovered <path>` to see the source in
   context.
2. Characterize each cluster of uncovered lines: error/rescue path, edge-case
   branch, defensive guard, platform-specific code, dead code, debug/logging
   code, or core logic.
3. Check whether a spec for that file exists (specs mirror the lib path under
   `spec/`). Note whether the gap is "no spec at all", "spec exists but misses
   these paths", or "covered only indirectly by integration specs".
4. Judge the **risk** of each gap: what goes wrong for a user if this code is
   broken and no test notices? Be concrete.
5. Flag likely dead code separately: it should be deleted, not tested.

Do not pad the report: a high percentage with an untested critical error path
is worth more attention than modest coverage of formatting helpers.

## Step 6: Look beyond line percentages

Briefly assess, per major area, using the specs themselves:

- Whether coverage comes from focused unit specs or only from broad
  integration/end-to-end specs (high coverage via integration alone can hide
  weak assertions).
- Whether specs assert on behavior or merely execute code (spot-check a few
  specs per area; cite them).
- Cross-mode consistency: behavior that exists in both CLI and MCP mode should
  be tested in both.

Keep this qualitative and evidence-based; cite spec files and line numbers.

## Report

Write your analysis in the project root (or in the directory the invocation
names) as a Markdown file whose name is:
- today's date in UTC `%Y-%m-%d-%H-%M` format +
- '-test-coverage-analysis-' +
- your name (e.g. 'codex', 'claude', 'gemini', 'zai') +
- the `.md` extension.

The file should have the following structure:

---

### Executive Summary
- Commit cited, cov-loupe interface used (MCP or CLI), suite result, and
  coverage file timestamp/staleness status.
- Overall line coverage (with and without tracked globs).
- The best- and worst-covered areas, and the top risk areas.
- A **one-line verdict** (e.g. *"Strong core coverage; error paths in the MCP
  tools are the main gap"*).

### Area Map
The hierarchy of logical areas from Step 3, showing for each area its parent,
its definition (file paths with line ranges and the code units they cover, or
globs for whole files), and criticality with reason. Mark the partition level used for reconciliation and
any overlapping cross-cutting areas. Explain why you carved the code this way.

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
- Spec status (none / partial / indirect only).
- Risk, with a concrete failure scenario.
- Recommendation: test to add (describe the scenario, not the code), code to
  delete, or "acceptable as is" with the reason.

### Test Quality Observations
Findings from Step 6, with citations.

### Data Caveats
Stale, skipped, missing, or unreadable files; branch coverage being out of
scope; ambiguous line assignments at area boundaries; anything else that
limits confidence in the numbers.

### Prioritized Recommendations
A numbered list, highest value first. For each: the area, the effort (S/M/L),
the expected coverage or risk improvement, and a ready-to-use prompt the user
can give an AI assistant to implement it.

### Appendix: Commands Run
Every cov-loupe call (MCP tool name and arguments, or CLI command) used to
produce the numbers, plus any aggregation script, so the report can be
reproduced.

---

End your final message with the report's path and the one-line verdict, or,
if you stopped early, with the error. A headless caller can then find the
outcome without parsing the rest of your output.
