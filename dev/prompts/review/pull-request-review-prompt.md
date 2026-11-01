# Pull Request Review

Review the referenced pull request and report on its quality. Review only; do
not edit files, push, comment on the PR, approve, or merge.

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. If no pull request (number, URL, or branch) was given, ask for one.
3. Read [AGENTS.md](../../../AGENTS.md) and
   [ai-code-evaluator-guidelines.md](../guidelines/ai-code-evaluator-guidelines.md).
   Do not report the intentional design decisions the guidelines describe.

## Gather Context

- Read the PR title, description, linked issues, and existing review comments
  to establish its stated purpose.
- Get the full diff against the PR's base branch (for example
  `git --no-pager diff origin/main...<pr-branch>`), not just the latest commit.
- Read enough of the surrounding code to judge each change in context.
- Where feasible, check out the branch and run `bundle exec rubocop` and the
  specs touching the changed code. `bundle exec rspec` rewrites
  `coverage/coverage.json`; do not run it if other agents may be reading that
  file. Say which checks you ran and which you skipped.

## Evaluate

- **Correctness:** Does it do what it claims, including edge cases and error
  paths? Look for regressions in the CLI, MCP server, and library API, which
  share one coverage model.
- **Scope:** Does it change anything beyond its stated purpose? Unrelated
  changes should be split out.
- **Tests:** Do specs cover the new behavior and the failure modes, asserting
  behavior rather than merely executing code? Specs belong in
  `spec/**/*_spec.rb` mirroring the `lib/` path. Use cov-loupe (MCP server
  preferred, CLI otherwise) for coverage of changed files.
- **Compatibility:** Does it change public CLI options, MCP tools or
  arguments, payload shapes, or `@api public` Ruby API? If so, is the change
  noted in `RELEASE_NOTES.md` (under `### Breaking` if incompatible), and is
  `SCHEMA_VERSION` bumped for incompatible payload changes?
- **Documentation:** Are user and developer docs updated where behavior
  changed? Are new classes and modules tagged `@api public` or `@api private`?
- **Simplicity:** Is this the least complex solution? Is there duplication that
  an existing helper already covers?
- **Consistency and idiom:** Does it match the existing architecture, naming,
  and Ruby idioms (Enumerable methods, early returns, clear names)?

## Report

Start with a one-line verdict: ready to merge, needs minor changes, or needs
significant changes.

Then list findings, most severe first. For each, give the `path:line`, what is
wrong, why it matters, and a concrete fix. Mark each as blocking or
non-blocking, and as verified (reproduced or confirmed in the code) or
inferred.

Skip sections with nothing to report. Do not pad the review with praise or with
alternatives that are no better than what the PR does.
