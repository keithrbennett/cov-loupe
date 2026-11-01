# Review and Revise Documentation as Necessary

**Purpose:** Keep the project's Markdown documentation accurate, clear,
complete, and internally consistent.

## Preconditions

Before you begin:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.

---

## Scope

Examine all tracked Markdown files at the repository root (`*.md`), in
`docs/**/*.md`, and in `examples/**/*.md`.

Exceptions:

- `docs/user/migrations/**/*.md`: each guide describes the release it was
  written for. Fix broken links and typos only; never update them to reflect
  later changes.
- `docs/dev/arch-decisions/**/*.md`: these are decision records. Correct
  factual errors about the current code, but do not rewrite the history of a
  decision.
- `dev/prompts/**/*.md` and `docs/user/prompts/**/*.md` are prompts, not
  documentation; leave them alone unless they reference something that no
  longer exists.

## What to Look For

### Accuracy

- Claims that no longer match the code (CLI flags, method names, output
  formats, file paths).
- Code examples that produce different output than documented, or that refer to
  removed features.
- Version numbers, dependency names, or configuration keys that have changed.

### Clarity

- Sections that assume prior knowledge not provided in the doc or a
  clearly-linked prerequisite.
- Ambiguous pronouns or unexplained jargon — if the meaning is unclear on first
  read, rewrite it.
- Paragraphs that mix distinct topics; split or reorganise them.
- Over-long explanations where a concise rewrite would preserve meaning with
  less noise.

### Completeness

- Missing prerequisites: if a command requires setup, the setup must be
  described or linked.
- Gaps between what a feature does and what the docs say it does.
- New CLI subcommands, MCP tools, or options not yet documented.

### Link Integrity

Check internal links (relative Markdown paths) and anchor links
(`#heading-id`):

- Verify that the target file exists at the referenced path.
- Verify that named anchors (`#section-name`) match an actual heading in the
  target document.
- Check that bidirectional navigation links exist where expected (e.g., a
  top-level README links to a specialist doc, and that doc links back with text
  like `Back to main README`).

### Duplication

- If the same point is explained in multiple documents, decide which is the
  canonical location and replace the others with a brief note and a link to it.
- Do not duplicate content that is already maintained elsewhere — link instead.

### Code Examples

- Confirm that shell/CLI examples use current flag names and produce valid
  output.
- For thorough validation of all runnable examples across the docs, use
  [`dev/prompts/validate/test-documentation-examples.md`](../validate/test-documentation-examples.md).

## Special Cases

### MkDocs Include-Markdown Stubs

Some files under `docs/` are intentional single-line stubs that use the MkDocs
`include-markdown` plugin to pull in content from the repository root. Do
**not** flag these as incomplete. See
[`dev/prompts/guidelines/ai-code-evaluator-guidelines.md` - MkDocs
Include-Markdown
Stubs](../guidelines/ai-code-evaluator-guidelines.md#mkdocs-include-markdown-stubs)
for the full explanation.

## Actions to Take

1. **Fix in place** — edit the doc file directly; no separate report is needed
   unless the scope of changes warrants a summary.
2. **Prefer linking over duplicating** — when the same information belongs in
   two places, keep the authoritative copy and add a short cross-reference
   elsewhere.
3. **Match existing tone** — keep edits consistent with the surrounding prose
   style.
4. **Do not rewrite for rewriting's sake** — only change what is inaccurate,
   unclear, or missing.

## Constraints

- Treat the code as the source of truth. Do not alter code files; if the code
  looks wrong rather than the docs, report it instead.
- Verify claims by running the CLI (`bundle exec exe/cov-loupe --help` and the
  documented commands) rather than trusting the existing text.
- If `mkdocs` is already installed, run
  `mkdocs build --strict --site-dir <temp dir>` after editing and fix any new
  warnings. Do not run `bin/build-docs` unless the user agrees: it installs
  Python packages and creates `.docs-venv/`.
- Do not run `git commit`. Stage only the documentation files you changed, and
  propose a concise commit message describing what was corrected and why.
