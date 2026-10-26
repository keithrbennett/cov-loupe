# Test Coverage by Component Prompt

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
- Your task is to produce a report of line coverage **rolled up by higher-level
  components and subsystems**, not just a per-file list, and to judge where the
  gaps actually matter.
- Get every coverage number from cov-loupe. Do not compute coverage yourself
  from `coverage/coverage.json`, and do not estimate it by reading specs.
  Prefer the cov-loupe MCP server; if it is unavailable, use `cov-loupe` in CLI
  mode (`bundle exec exe/cov-loupe -h` in this repo). Say in the report which
  one you used.
- Use source and spec files only to define components and to judge the
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

## Step 3: Define components and subsystems

Build a component map before computing any rollups.

1. Start from the directory and namespace structure (for this repo, the
   directories under `lib/cov_loupe/`, plus the top-level files directly in
   it). Read entry points and `require` graphs (e.g. `lib/cov_loupe.rb`,
   `lib/cov_loupe/loaders/`) to see how pieces connect.
2. Group directories into **subsystems** by responsibility, not just by
   folder name. Each subsystem should answer "what does this part of the
   system do for the user?" For this repo, plausible groupings include (verify
   against the actual code; do not take this list as given):
   - Coverage data loading and the coverage model
   - Path resolution and staleness detection
   - Coverage calculation and reporting
   - Output formatting and presentation
   - CLI (option parsing, subcommands, commands)
   - MCP server and tools
   - Configuration, error handling, and logging
   - Validation / predicate evaluation
   - Scripts, resources, and miscellaneous top-level files
3. Assign every tracked source file to exactly one component. Files that
   don't fit go in an explicit "Other" component; do not drop them.
4. Express each component as one or more tracked globs (for example
   `lib/cov_loupe/tools/**/*.rb,lib/cov_loupe/mcp_server.rb,lib/cov_loupe/base_tool.rb`).
   Verify that the globs together match every file exactly once; report any
   overlaps or orphans you had to fix.
5. Classify each component's **criticality** (High / Medium / Low) and give
   a one-line reason. Weigh: user-visible behavior, data correctness, security
   boundaries (e.g. code evaluation, file system access), error paths, and
   public API (`@api public` YARD tags).

## Step 4: Compute coverage per component

For each component:

1. Run project totals with that component's globs
   (`project_coverage_totals` with `tracked_globs`, or
   `cov-loupe -f J -g '<globs>' totals`). Record covered, uncovered, total
   lines, percentage, file count, and files without coverage.
2. Run the file list with the same globs, sorted ascending, to find the
   component's weakest files.
3. Confirm that per-component line totals add up to the project total for the
   same overall globs. If they don't, find the overlap or orphan and fix the
   map; state any remaining discrepancy.

Then roll components up into subsystems the same way (a subsystem's numbers
come from cov-loupe with the union of its globs, not from averaging component
percentages).

## Step 5: Examine the gaps

For every file below 90% in a High-criticality component, every file below
75% elsewhere, and every tracked file with no coverage data:

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

Do not pad the report: high percentage with an untested critical error path
is worth more attention than 85% coverage of formatting helpers.

## Step 6: Look beyond line percentages

Briefly assess, per subsystem, using the specs themselves:

- Whether coverage comes from focused unit specs or only from broad
  integration/end-to-end specs (high coverage via integration alone can hide
  weak assertions).
- Whether specs assert on behavior or merely execute code (spot-check a few
  specs per subsystem; cite them).
- Cross-mode consistency: behavior that exists in both CLI and MCP mode should
  be tested in both.

Keep this qualitative and evidence-based; cite spec files and line numbers.

## Report

Write your analysis in a Markdown file whose name is:
- today's date in UTC `%Y-%m-%d-%H-%M` format +
- '-coverage-by-component-' +
- your name (e.g. 'codex', 'claude', 'gemini', 'zai') +
- the `.md` extension.

The file should have the following structure:

---

### Executive Summary
- Commit cited, cov-loupe interface used (MCP or CLI), suite result, and
  coverage file timestamp/staleness status.
- Overall line coverage (with and without tracked globs).
- The best- and worst-covered subsystems, and the top 3 risk areas.
- A **one-line verdict** (e.g. *"Strong core coverage; error paths in the MCP
  tools are the main gap"*).

### Component Map
A table listing each subsystem, its components, the globs used, file count,
and criticality with reason. Note any files that were hard to place.

### Coverage by Subsystem
A table sorted ascending by percentage:

| Subsystem | Criticality | Files | Covered | Total | % | Files w/o data | Weakest file (%) |
|-----------|-------------|-------|---------|-------|---|----------------|------------------|

Follow with a short paragraph per subsystem interpreting the numbers.

### Coverage by Component
The same table at component granularity, sorted ascending.

### Gap Analysis
For each gap from Step 5, grouped by subsystem and ordered by risk:
- File and uncovered line numbers (as reported by cov-loupe).
- What the code does and the gap's category.
- Spec status (none / partial / indirect only).
- Risk (High / Medium / Low) with a concrete failure scenario.
- Recommendation: test to add (describe the scenario, not the code), code to
  delete, or "acceptable as is" with the reason.

### Test Quality Observations
Findings from Step 6, with citations.

### Data Caveats
Stale, skipped, missing, or unreadable files; branch coverage being out of
scope; anything else that limits confidence in the numbers.

### Prioritized Recommendations
A numbered list, highest value first. For each: the subsystem, the effort
(S/M/L), the expected coverage or risk improvement, and a ready-to-use prompt
the user can give an AI assistant to implement it.

### Appendix: Commands Run
Every cov-loupe call (MCP tool name and arguments, or CLI command) used to
produce the numbers, so the report can be reproduced.

---
