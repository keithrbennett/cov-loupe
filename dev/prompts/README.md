# AI Prompts for cov-loupe Development

This directory contains prompts for AI coding assistants to help with codebase maintenance and improvement.

## General Precondition

Unless a prompt explicitly says otherwise: if you are not in the project root,
inform the user, state your current working directory, and wait for
confirmation before proceeding so they can choose to start a new session in the
project root. Most prompts restate this, because they are usually pasted into an
agent on their own.

Review prompts write their reports to `untracked/` (gitignored) and never
change tracked files; improve prompts edit files and stage them, but never
commit.

## Quick Reference

### Review Code

**[State of the Code Base](review/state-of-the-code-base-prompt.md)**
- **When:** Periodic health checks, understanding overall state, pre-release assessments
- **Output:** Balanced assessment (strengths + weaknesses) with weighted scoring by section, written to a timestamped Markdown file
- **Question answered:** "How are we doing overall?"

**[Identify Action Items](review/identify-action-items.md)**
- **When:** Planning sprints, "what needs fixing NOW?"
- **Output:** Issues-only report with severity/effort, actionable prompts for each
- **Question answered:** "What should we fix next?"
- **Time:** 1-2 hours

**[Verify Code Changes](review/verify-code-changes.md)**
- **When:** After implementing a feature/fix, before committing
- **Output:** Verdict plus findings on correctness, completeness, simplicity, and tests, written to `untracked/`
- **Question answered:** "Did I do this right?"
- **Time:** 10-30 minutes

**[Review Documentation](review/review-documentation.md)**
- **When:** Before a release or after large doc changes
- **Output:** Report of inaccurate, unclear, missing, or inconsistent documentation (no changes made)
- **Question answered:** "Are the docs right?"

**[Pull Request Review](review/pull-request-review-prompt.md)**
- **When:** Reviewing a pull request
- **Output:** Verdict plus findings on correctness, scope, tests, compatibility, and docs (no changes made)
- **Question answered:** "Is this PR ready to merge?"

**[Release Review](review/release-review.md)**
- **When:** Any time before a release, with or without having run `rake release:bump` first
- **Output:** Checklist of what is needed to release (target version, release notes gaps, schema version, major-release docs, cleanup, remaining steps)
- **Question answered:** "What would I need to do to release?" / "What is left before I can release?"
- **Time:** 10-20 minutes

**[CLI / MCP Consistency Audit](review/cli-mcp-consistency-audit.md)**
- **When:** After changing CLI commands/options or MCP tools/arguments, before releases
- **Output:** Report of capability gaps, behavioral differences, and error-handling and documentation mismatches between the CLI and MCP server, written to `untracked/` (no changes made)
- **Question answered:** "Can everything be done, the same way, from either interface?"

### Improve Code/Docs

**[Refactor Test Suite](improve/refactor-test-suite.md)**
- **When:** Tests are verbose, duplicated, or unclear
- **Output:** Shorter, de-duplicated specs (spec files only), Rubocop clean, plus a summary
- **Time:** 30 min - 2 hours

**[Simplify Code Logic](improve/simplify-code-logic.md)**
- **When:** Code is hard to understand or maintain
- **Output:** Simplified code or explanatory comments, with behavior unchanged, plus a summary
- **Time:** 30 min - 1 hour

**[Update Documentation](improve/update-documentation.md)**
- **When:** Docs are outdated, unclear, or incomplete
- **Output:** Revised markdown files with accurate, clear content
- **Time:** 1-2 hours

### Validate Content

**[Test Documentation Examples](validate/test-documentation-examples.md)**
- **When:** After doc changes, before releases
- **Output:** Report of working/broken code examples in documentation (no changes made)
- **Time:** 15-30 minutes

### User-Facing Prompts

[docs/user/prompts/](../../docs/user/prompts/README.md) holds prompts shipped
for cov-loupe's users, such as the
[Test Coverage Analysis](../../docs/user/prompts/test-coverage-analysis-prompt.md)
prompt that the State of the Code Base review defers to. Keep those
project-agnostic.

## Guidelines

See [guidelines/ai-code-evaluator-guidelines.md](guidelines/ai-code-evaluator-guidelines.md)
for context on design decisions that AI reviewers should understand before
flagging issues. This document explains:

- Security considerations (validate command, file system operations, rate limiting)
- Performance trade-offs (memory-based coverage data)
- Code quality decisions (RuboCop metrics cops, method length)
- Documentation structure (MkDocs includes)

AI analysis tools should consult this document before reporting issues to avoid
false positives on intentional design decisions.

## Removed Prompts

`architectural-review-and-actions-prompt.md`, `investigate-and-report-issues-prompt.md`,
and `produce-action-items-prompt.md` were merged into
[Identify Action Items](review/identify-action-items.md).
