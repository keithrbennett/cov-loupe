# Release Review

**Purpose:** Produce a checklist of what still needs to be done to release
cov-loupe, based on the actual state of the repository. It works both before
and after `rake "release:bump[VERSION]"`. This is advisory and complements the
scripts: `release:bump` makes the mechanical edits and `bin/pre-release-check`
is the hard gate.

## When to Use This

- At any point, to answer "what would I need to do to release?" (before the bump)
- After running `release:bump`, before committing and pushing
  ("what is left?")

Do not use this to replace `bin/pre-release-check`; it does not verify CI, the
clean tree, or the built gem.

---

## Preconditions

1. If you are not in the project root, inform the user, state your current
   working directory, and wait for confirmation before proceeding.
2. Open the report by citing the most recent git commit.
3. Run `git status`. List any uncommitted changes. They are expected if
   `release:bump` was just run; otherwise note them as items to resolve. Do not
   modify any files.
4. Limit the review to git-tracked files, plus untracked files reported by
   `git status` (for the cleanup step).

---

## Your Role & Task

You are a release manager. Read `docs/dev/RELEASING.md` (the canonical
checklist, which may have changed since this prompt was written) and
determine, from the repository's actual contents, the status of every item
that requires judgment. Do not re-run tests, Rubocop, or CI; those are covered
by `bin/pre-release-check`.

### 1. Establish the release state and target version

- Read `VERSION` from `lib/cov_loupe/version.rb`, the `## Unreleased` section
  of `RELEASE_NOTES.md`, and the newest `## v...` heading.
- Find the previous *stable* release tag (`git tag --sort=-v:refname`, ignoring
  `.pre.` tags).
- Decide whether the bump has been done. It **has** if the newest `## v...`
  heading matches `VERSION`, is not already tagged, and `## Unreleased` is empty.
  It **has not** if there is content under `## Unreleased`, or `VERSION` equals
  an already-tagged release or a prerelease that is not the intended target.
  If the state is ambiguous, say so and ask.
- Determine the target version:
  - Bumped: the target is `VERSION`.
  - Not bumped: if the user named a target version, use it. Otherwise
    recommend one using semantic versioning from the changes found in step 2
    (breaking change: major; new feature: minor; fixes only: patch), explain
    the reasoning, and label it a recommendation for the maintainer to confirm.
    Do not ask before proceeding; continue the review against the
    recommended version.
- Classify the target. It is a **major release** if it is `N.0.0` and the
  previous stable tag has a lower major number, even when `version.rb`
  currently holds a `.pre.` version of the same major. State the classification
  and the reasoning. Note whether the target is a prerelease (`.pre.N`).

### 2. Compare changes against release notes

- Review `git --no-pager log --oneline <previous-stable-tag>..HEAD` and the
  diff of `lib/`, `exe/`, and `docs/`.
- Compare against the release notes for this release: the `## v<target>`
  section if bumped, or the `## Unreleased` section if not.
- List user-visible changes (CLI options, MCP tools, output formats, library
  API, error behavior, dependencies, Ruby version requirement) that are missing
  from the notes.
- List note entries that do not correspond to any actual change.
- Flag any incompatible change that is not under `### Breaking`.

### 3. Schema version

- Check whether any structured payload shape changed incompatibly since the
  previous stable tag (`git --no-pager diff <tag> -- lib/cov_loupe/schemas/`
  and the code that builds payloads).
- If so, verify `CovLoupe::SCHEMA_VERSION` was incremented, a new
  `schemas/vN/` directory exists, earlier schema directories are unchanged, and
  the pinned value in `spec/cov_loupe/version_spec.rb` matches.

### 4. Major-release documentation (major releases only)

Verify each item in the "Major releases" section of `docs/dev/RELEASING.md`:

- `docs/user/migrations/MIGRATING_TO_V<N>.md` exists and has an example for
  every entry under `### Breaking`.
- The guide is linked from `docs/user/migrations/README.md`, `README.md`,
  `docs/user/README.md`, `docs/user/INSTALLATION.md`, and `mkdocs.yml`.
- No stale version references remain (`rg 'v<N-1>' docs README.md`, then judge
  which hits are legitimate history).

Per the repository's migration-doc convention, older migration guides must
describe their own versions only; do not recommend retroactive edits to them.

### 5. Documentation accuracy

- Spot-check `README.md` and `docs/` against the changes found in step 2:
  examples, option names, tool names, and version numbers.
- For a thorough example check, recommend
  `dev/prompts/validate/test-documentation-examples.md` rather than doing it
  here.

### 6. Cleanup

- From `git status`, classify each untracked or modified file as: commit,
  add to `.gitignore`, delete, or expected release change.
- Look for stray temp files or local notes listed in the Cleanup section of
  `docs/dev/RELEASING.md`.

### 7. Remaining process steps

List the not-yet-done steps from `docs/dev/RELEASING.md`, in order, marking any
that the repository state shows are already done (for example, an existing tag
or an `origin/main` that matches `HEAD`):

- Bump (if not done): give the exact command,
  `bundle exec rake "release:bump[<target>]"`, and say it should run after the
  documentation gaps found above are fixed or at least known, since the bump
  moves the `## Unreleased` content under the new version heading.
- Commit and push, `bin/pre-release-check`, install test, tag at the built SHA,
  push, `gem push`, GitHub release.

---

## Output Format

Open with the commit citation, then:

- Bump state (done or not done) and the evidence
- Previous stable tag
- Target version (given, or recommended with reasoning)
- Classification: major, minor, patch, or prerelease

Then give a single checklist, grouped by the sections above:

- `[ ]` needs action, with the file path and what to do
- `[x]` verified OK, with a few words of evidence
- `[?]` needs the maintainer's judgment, with the question to answer

Put all `[ ]` and `[?]` items first in a short "Before you bump" (or, if the
bump is done, "Blocking before commit") summary. Where a gap suggests a script
improvement (for example, a check that could be automated in
`bin/pre-release-check`), mention it at the end as a prompt the maintainer can
use later. Do not implement it.

Do not edit files, stage, commit, tag, or push.
