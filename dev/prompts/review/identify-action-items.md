# Identify Action Items

**Purpose:** Identify and prioritize issues that need fixing NOW. This is a
problems-focused review (not a balanced assessment).

## When to Use This

- Planning sprints or development cycles
- Identifying technical debt to tackle
- Preparing bug-fix releases
- Answering: "What should we fix next?"

For a balanced assessment showing strengths AND weaknesses, use `comprehensive-codebase-review.md` instead.

---

## Preconditions

Before you begin the report:

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding so they can
   choose to start a new session in the project root.
2. Always open the report by citing the most recent git commit at the time you
   begin writing.
3. Limit the review strictly to git-tracked files.
4. If `git status` shows uncommitted changes, inform me, ask for confirmation to
   proceed, and-if I consent-include those `git status` details immediately
   after the commit citation.

---

## Your Role & Task

- You are a senior software architect and code reviewer.
- Your task is to analyze this code base thoroughly and identify issues needing
  immediate attention.
- Focus on: bugs, defects, security vulnerabilities, performance bottlenecks,
  technical debt, weaknesses, risks, ambiguities, and other areas requiring
  improvement.
- **This is NOT a balanced review** - focus on problems, not strengths.

---

## Exclusions & Balance Guidance

### Consult Guidelines First

**CRITICAL:**

- Disregard any issues included in
  `dev/prompts/guidelines/ai-code-evaluator-guidelines.md` unless your
  objections are not covered in that document.
- For architectural issues, consult `docs/dev/arch-decisions` to see if the issue has already been considered.

**Repeating for emphasis:** Disregard any issues included in
`dev/prompts/guidelines/ai-code-evaluator-guidelines.md` unless your objections
are not covered in that document.

### Be Balanced (Not Excessively Critical)

- Do not list issues that are not real issues.
- If there is a tradeoff between A and B, and the justification is sound and
  documented (e.g., in ai-code-evaluator-guidelines.md), do not penalize the
  code base for that tradeoff.
- Be fair in your severity assessments; sometimes trivial issues are overweighted.
- Investigate thoroughly for real issues, but maintain perspective on their actual impact.

---

## Tooling

- Use the `cov-loupe` MCP server *as an MCP server* (not a command line
  application with args) to find information about test coverage.
- Only if you are unable to use the cov-loupe MCP server, use `cov-loupe` in
  CLI mode (run `cov-loupe -h` for help).

---

## Report Structure

### For Each Issue Found

Delimit each issue with horizontal lines and headlines. Number each issue.

**Required sections:**

1. **Headline & Description:** Clear, concise explanation of the issue.
2. **Assessment:**
   - **Severity:** High/Medium/Low
   - **Effort to Fix:** High/Medium/Low
   - **Impact if Unaddressed:** What happens if we don't fix this?
3. **Strategy:** High-level approach for addressing the issue.
4. **Actionable Prompt:** Provide a specific, copy-paste-ready prompt that can
   be given to an AI coding agent to fix or improve this specific issue. End
   the prompt with the following instruction:

   > After completing the fix, propose a detailed commit message. Focus on why
   > the approach was chosen and any non-obvious decisions or tradeoffs.
   > Describe what the tests verify in terms of expected behavior, not the
   > mechanics of how they were written. Omit restatements of what the diff
   > already shows.

**Example format:**

---

## Issue: Insecure Password Storage

### Description
User passwords are stored in plain text in the database.

### Assessment
- **Severity:** High
- **Effort to Fix:** Medium
- **Impact if Unaddressed:** Critical security vulnerability; user accounts easily compromised.

### Strategy
Replace plain text storage with bcrypt hashing. Update authentication logic to
hash passwords on registration and verify hashed passwords on login.

### Actionable Prompt
```
Update the user authentication system to use bcrypt for password hashing. Specifically:
1. Add bcrypt gem to Gemfile
2. Update User model to hash passwords before saving
3. Update authentication logic to compare hashed passwords
4. Add migration to hash existing plain text passwords

After completing the fix, propose a detailed commit message. Focus on why the approach was chosen 
and any non-obvious decisions or tradeoffs. Describe what the tests verify in terms of expected behavior — 
not the mechanics of how they were written. Omit restatements of what the diff already shows.
```

---

### Summary Table

At the end of the file, produce a markdown table that summarizes ALL issues,
ordered by priority (considering severity, effort, and impact):

| Brief Description (<= 50 chars) | Severity (H/M/L) | Effort (H/M/L) |
| Impact if Unaddressed | Link to Detail |
| :--- | :---: | :---: | :--- | :--- |
| ... | ... | ... | ... | [See below](#issue-title) |

**Priority ordering:** Issues should be ordered to maximize value. Generally this means:
- Critical severity with low-to-medium effort → highest priority
- High severity regardless of effort → high priority
- Medium severity with low effort → medium-high priority
- Low severity with high effort → lowest priority

Use your judgment to order issues for optimal value delivery.

---

## Output File

Write your analysis in a Markdown file in the untracked/ dir (mkdir if necessary) whose name is:

- today's date in UTC `%Y-%m-%d-%H-%M` format +
- `-prioritized-action-items-` +
- your name (e.g. `codex`, `claude`, `gemini`, `zai`) +
- the `.md` extension.

**Example:** `2026-01-08-19-45-prioritized-action-items-claude.md`

---

## Constraints

- **DO NOT MAKE ANY CODE CHANGES. REVIEW ONLY.**
- Focus exclusively on identifying and prioritizing problems.
- Do not include "strengths" or "what's going well" sections.
