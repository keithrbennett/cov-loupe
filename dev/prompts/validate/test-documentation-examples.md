# Test Documentation Examples

**Purpose:** Verify that the command examples in the documentation run as
written and produce the documented output. Report only; do not edit files.

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Make sure `coverage/coverage.json` exists and is current. If it is missing
   or stale, run `bundle exec rspec` once to regenerate it (skip this if other
   agents may be reading that file, and say so in the report).

---

## When to Use This

- After documentation changes
- Before releases
- After CLI, MCP, or library API changes that might affect examples

## Scope

Test the examples in:

- `README.md`
- `docs/user/**/*.md`
- `docs/dev/**/*.md`
- `examples/**/README.md`

Do not test:

- `docs/user/migrations/**/*.md`: they show older versions on purpose.
- `docs/dev/arch-decisions/**/*.md`: they are historical records.
- The MkDocs `include-markdown` stubs under `docs/`; test the files they
  include instead.

## Safety

Apart from regenerating `coverage/` in the preconditions, run only commands
that read data or write to a temporary directory. Do **not** run commands
that:

- install software or gems (`gem install`, `brew`, `pip install`),
- change the user's configuration, such as registering an MCP server with an
  AI client (`claude mcp add`, `codex mcp add`, editing client config files),
- publish, tag, push, or release (`gem push`, `git push`, `rake release:*`).

Check such commands by reading them against the code and help output instead,
and list them in the report as "checked, not run".

## Process

### 1. Extract the examples

Collect fenced blocks marked `bash`, `sh`, `shell`, or `console`, inline code
that is clearly a runnable command, MCP JSON-RPC examples, and Ruby snippets
that call the library API. Note any output shown with them.

### 2. Run each example

1. Run it from the directory the documentation implies (usually the project
   root), using `bundle exec exe/cov-loupe` in place of `cov-loupe`.
2. Pipe MCP JSON-RPC examples to `bundle exec exe/cov-loupe -m mcp`.
3. Create any files the example assumes in a temporary directory, not in the
   repository.
4. Check the exit code (0 unless the docs show a failure), compare the output
   with the documented output (ignoring values that legitimately vary, such as
   coverage percentages, timestamps, and absolute paths), and check that
   documented error examples produce that error.

### 3. Record failures

For each failure, record the file and line, the command, the documented and
actual results, and a suggested fix to either the documentation or, if the
code looks wrong, the code.

## Common Causes

- Renamed or removed options and subcommands
- Global options placed after the subcommand (cov-loupe requires them before)
- Changed JSON fields, table columns, or error text
- Working-directory or path assumptions
- Missing setup steps

## Output Format

If every example passes, report that briefly:

```text
Tested X examples across Y files; all passed. Checked, not run: Z (listed below).
```

Otherwise, write a report like this:

~~~markdown
# Documentation Example Test Results

**Date:** YYYY-MM-DD
**Tested Files:** X
**Total Examples:** Y
**Failed:** Z

## Failures

### README.md

#### Line 42: list command

**Command:**
```bash
cov-loupe list --format json
```

**Expected:** JSON output with coverage data

**Actual:**
```text
Global option(s) must come BEFORE the subcommand.
You used: cov-loupe list --format json
Correct: cov-loupe --format json list
```

**Suggested Fix:** Put the global option before the subcommand:
```bash
cov-loupe --format json list
```

## Checked, Not Run

- `docs/user/INSTALLATION.md` line 12: `gem install cov-loupe` (install command)

## Summary

- Fix the option order in README.md line 42
~~~

Do not modify files, open issues, or commit. The report is the deliverable;
the user decides which fixes to make.
