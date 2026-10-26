# Test Coverage Analysis Prompt

### Preconditions

Before you begin the analysis:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding so they can
   choose to start a new session in the project root.
2. Always open the report by citing the most recent git commit at the time you
   begin writing.
3. If `git status` shows uncommitted changes, inform me, ask for confirmation to
   proceed, and-if I consent-include those `git status` details immediately
   after the commit citation.
4. Limit the analysis strictly to git-tracked files.

----

- You are a senior engineer assessing the test suite of this project.
- Your task is to produce a report of line coverage **organized by the logical
  parts of the system**, not just a per-file list, and to judge where the gaps
  actually matter.
- Get every coverage number from cov-loupe. Do not compute coverage yourself
  from `coverage/coverage.json`, and do not estimate it by reading specs.
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
2. If the suite fails, report the failures and ask whether to continue: a
   failing suite can make coverage numbers misleading.
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
most precise, targeted analysis, so choose the areas that best reveal where
testing is strong or weak; do not settle for the directory layout if a
different cut tells more.

1. Read the code to understand its structure: entry points and `require`
   graphs (e.g. `lib/cov_loupe.rb`, `lib/cov_loupe/loaders/`), namespaces, and
   how responsibilities flow between parts.
2. Define **logical areas at whatever granularity is meaningful**. An area can
   be:
   - a broad grouping of several directories (e.g. "everything the CLI path
     uses"),
   - a single directory or namespace,
   - a slice of one (e.g. the staleness checks inside the coverage model, or
     the argument-validation part of the MCP tools),
   - or a cross-cutting concern spanning many places (e.g. error handling,
     path resolution, output formatting across CLI and MCP).
3. Arrange the areas in a hierarchy where that helps (a broad area containing
   narrower ones), and nest as deep as it is useful. Cross-cutting areas may
   overlap others; say so where they do.
4. Express each area as one or more tracked globs where possible (for example
   `lib/cov_loupe/tools/**/*.rb,lib/cov_loupe/mcp_server.rb,lib/cov_loupe/base_tool.rb`).
   When an area is only part of a file, name the file plus the methods or line
   ranges that belong to it; its numbers then come from per-line cov-loupe data
   (Step 4) rather than from globs.
5. Make sure at least one level of the hierarchy is a **complete partition**:
   every tracked source file belongs to exactly one area at that level, with an
   explicit "Other" area for files that fit nowhere. This level is what the
   totals are reconciled against.
6. Give each area a **criticality** judgment with a short reason. Treat it as a
   continuum, not a fixed set of buckets: place each area relative to the
   others and explain what drives the placement. Weigh user-visible behavior,
   data correctness, security boundaries (e.g. code evaluation, file system
   access), error paths, public API (`@api public` YARD tags), and how often
   the code runs.

## Step 4: Compute coverage per area

For each area:

1. For a glob-defined area, run project totals with that area's globs
   (`project_coverage_totals` with `tracked_globs`, or
   `cov-loupe -f J -g '<globs>' totals`). Record covered, uncovered, total
   lines, percentage, file count, and files without coverage. Run the file
   list with the same globs, sorted ascending, to find the area's weakest
   files.
2. For a sub-file area, use `file_coverage_detailed` /
   `cov-loupe -f J detailed <path>` and count the covered and coverable lines in
   the area's line ranges. State that these numbers were derived from per-line
   data.
3. Get a broader area's numbers from cov-loupe with the union of its
   children's globs, not by averaging child percentages.
4. Confirm that the totals for the partition level from Step 3 add up to the
   project total for the same overall globs. If they don't, find the overlap or
   orphan and fix the map; state any remaining discrepancy.

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

Write your analysis in a Markdown file whose name is:
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
its definition (globs, or file plus methods/line ranges), file count, and
criticality with reason. Mark the partition level used for reconciliation and
any overlapping cross-cutting areas. Explain why you carved the code this way.

### Coverage by Area
One table per hierarchy level that is worth showing, each sorted ascending by
percentage:

| Area | Criticality | Files | Covered | Total | % | Files w/o data | Weakest file (%) |
|------|-------------|-------|---------|-------|---|----------------|------------------|

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
scope; numbers derived from per-line data; anything else that limits
confidence in the numbers.

### Prioritized Recommendations
A numbered list, highest value first. For each: the area, the effort (S/M/L),
the expected coverage or risk improvement, and a ready-to-use prompt the user
can give an AI assistant to implement it.

### Appendix: Commands Run
Every cov-loupe call (MCP tool name and arguments, or CLI command) used to
produce the numbers, so the report can be reproduced.

---
