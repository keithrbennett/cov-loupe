# AI Prompts for cov-loupe Development

This directory contains prompts for AI coding assistants to help with codebase maintenance and improvement.

## General Precondition

Unless a prompt explicitly says otherwise: if you are not in the project root,
inform the user, state your current working directory, and wait for
confirmation before proceeding so they can choose to start a new session in the
project root.

## Quick Reference

### Review Code

**[Comprehensive Codebase Review](review/comprehensive-codebase-review.md)**
- **When:** Periodic health checks, understanding overall state, pre-release assessments
- **Output:** Balanced assessment (strengths + weaknesses) with scoring across 10 dimensions
- **Question answered:** "How are we doing overall?"
- **Time:** 2-4 hours

**[Identify Action Items](review/identify-action-items.md)**
- **When:** Planning sprints, "what needs fixing NOW?"
- **Output:** Issues-only report with severity/effort, actionable prompts for each
- **Question answered:** "What should we fix next?"
- **Time:** 1-2 hours

**[Verify Code Changes](review/verify-code-changes.md)**
- **When:** After implementing a feature/fix, before committing
- **Output:** Assessment of correctness, completeness, best practices
- **Question answered:** "Did I do this right?"
- **Time:** 10-30 minutes

### Improve Code/Docs

**[Refactor Test Suite](improve/refactor-test-suite.md)**
- **When:** Tests are verbose, duplicated, or unclear
- **Output:** Improved test code following DRY principles, Rubocop compliance
- **Time:** 30 min - 2 hours

**[Simplify Code Logic](improve/simplify-code-logic.md)**
- **When:** Code is hard to understand or maintain
- **Output:** Simplified code or added explanatory comments
- **Time:** 30 min - 1 hour

**[Update Documentation](improve/update-documentation.md)**
- **When:** Docs are outdated, unclear, or incomplete
- **Output:** Revised markdown files with accurate, clear content
- **Time:** 1-2 hours

### Validate Content

**[Test Documentation Examples](validate/test-documentation-examples.md)**
- **When:** After doc changes, before releases
- **Output:** Report of working/broken code examples in documentation
- **Time:** 15-30 minutes

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

## Deprecated Prompts

The following deprecated prompts were consolidated and removed from this directory:
- `architectural-review-and-actions-prompt.md` (merged into identify-action-items.md)
- `investigate-and-report-issues-prompt.md` (merged into identify-action-items.md)
- `produce-action-items-prompt.md` (merged into identify-action-items.md)

Use [Identify Action Items](review/identify-action-items.md) instead.
