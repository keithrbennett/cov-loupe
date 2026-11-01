# Verify Code Changes

Verify that a code change accomplishes its intent. Review only; do not edit
the code under review.

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Read [ai-code-evaluator-guidelines.md](../guidelines/ai-code-evaluator-guidelines.md)
   and do not report the intentional design decisions it describes.

## Inputs

- **Comparison point:** anything `git diff` accepts (a commit such as `HEAD~2`
  or a SHA, a branch, or a tag). If none is given, ask for it before doing
  anything else.
- **Intent:** what the change is meant to do (feature, bug fix, tests,
  documentation). If none is given, infer it from the commit messages in the
  range, and say at the top of the report that you did so.

Review `git --no-pager diff <comparison-point>` and, if the working tree has
uncommitted changes, include them and say so.

## Evaluate

Assess whether the change is:

- **Correct:** it does what the intent says, including edge cases and error
  paths, in every mode it affects (CLI, MCP, library).
- **Complete:** nothing needed is missing (callers, docs, release notes,
  schema version, `@api` tags).
- **Simple and concise:** no unnecessary code, and no hand-written logic that
  an existing helper, the standard library, or an already-installed gem
  provides.
- **Idiomatic:** it follows the project's conventions and Ruby best practices.
- **Tested:** specs cover the new behavior and its failure modes. Check
  coverage of the changed files with cov-loupe (MCP server preferred, CLI
  otherwise).

Where feasible, run `bundle exec rubocop` and the relevant specs, and say what
you ran.

Include only findings that would change what the author does. Omit remarks
such as "approach X could have been used, but the current one is a better
fit."

## Output

Write the report as Markdown to `untracked/` (create it if needed), named:

`<UTC timestamp %Y-%m-%d-%H-%M>-code-review-<agent>-<intent-slug>.md`

where `<agent>` is your lowercase tool name (e.g. `claude`, `codex`, `gemini`)
and `<intent-slug>` is a few hyphenated words describing the intent.
Example: `2026-01-08-19-45-code-review-claude-add-sort-option.md`.

Open with a one-line verdict, then the findings ordered by severity, each with
`path:line`, the problem, and a suggested fix.
