# Refactor Test Suite

**Purpose:** Make the specs clear, concise, and free of duplication without
reducing what they verify.

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Read the Testing Notes and Rubocop sections of
   [AGENTS.md](../../../AGENTS.md).

---

## What to Fix

Examine `spec/` and fix:

- **Duplicate tests** that verify the same behavior.
- **Tests of the test setup** (fixtures, doubles, helpers) rather than of
  production code.
- **Verbose assertions**, for example several `expect(x).to include('a')`
  lines that can be one `expect(x).to include('a', 'b', 'c')`.
- **Repeated test bodies** that differ only in data; iterate over an array of
  cases instead, or use shared examples (`it_behaves_like`).
- **Hard-to-follow tests** that would be clearer with intermediate variables,
  extracted helpers, or a brief comment.

## Constraints

- Change spec files only. If a test reveals a production bug, report it rather
  than fixing it here.
- Do not weaken assertions or drop coverage: each refactored test must still
  fail when the behavior it covers breaks.
- Run the affected spec files as you go
  (`bundle exec rspec spec/path_spec.rb`), then the full suite once at the end.
- Run `bundle exec rubocop` and fix every offense (`bundle exec rubocop -A`
  handles the autocorrectable ones). Add `--cache false` if cache writes fail
  in a sandbox.
- Do not run `git commit`. Stage only the spec files you changed and propose a
  concise commit message.

## Output

Summarize what you changed, grouped by the categories above, and any
production bugs you noticed.
