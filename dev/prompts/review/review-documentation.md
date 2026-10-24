# Review Documentation

Review the documentation of the repository in the current working directory.
Report only issues needing addressing. Do not make changes.

If the current working directory is not the repository root, say so, state
the current directory, and wait for confirmation before proceeding.

Documentation includes the README, any other Markdown files, help and usage
output, code comments that describe behavior, and sample files such as
example configs and prompts.

Evaluate whether the documentation is:

- **Accurate:** it matches what the code actually does. Check commands,
  flags, option names, method names, file names, paths, defaults, config
  keys, output formats, and version or prerequisite claims against the
  code. Examples run as written and produce the output shown.
- **Complete:** every user-facing feature, option, and behavior is
  documented, and nothing documented has been removed or renamed. Every
  setup step a command depends on is described or linked.
- **Consistent:** the documents agree with each other and with the help
  output, and use the same terms for the same things.
- **Usable by a newcomer:** someone starting from scratch can install,
  configure, and complete a first run by following it, without needing
  knowledge it doesn't provide. Steps are in a sensible order.
- **Clear and concise:** free of ambiguity, unexplained jargon, stale
  history, and text that is hard to find or easy to misread.
- **Free of duplication:** each topic has one canonical location. Where the
  same material is explained in several places, say which copy to keep
  and recommend replacing the others with a short link. Never recommend
  duplicating content that is maintained elsewhere.
- **Correctly linked:** relative links point to files that exist, and
  anchor links (`#section`) match a heading or explicit anchor in the
  target, both on the repository host and on the documentation site if
  the project builds one.

## Scope

- Report documentation problems only. Do not review the code except to
  verify what the documentation says about it.
- Ignore generated output and local scratch files, such as
  `agent-council-reports/`, `untracked/`, and built documentation sites.
- Treat the code as the source of truth when it disagrees with the
  documentation, unless the code's behavior looks like the bug; say so in
  that case.
- Skip purely stylistic preferences unless they affect accuracy, clarity,
  completeness, or maintainability.
- Files that consist only of a directive including another file (for
  example, an MkDocs `include-markdown` stub that publishes a root file on
  the documentation site) are intentional; do not report them as
  incomplete.

## Upcoming Release

Review the documentation as describing the upcoming release (the version in
the project's version file, such as `version.rb`, `package.json`, or
`pyproject.toml`), as if that release were already published. Do not report:

- that this version is not yet published, is a prerelease, or is marked
  unreleased;
- that install commands would fetch an older published release, or that
  the older release behaves differently from what the docs describe;
- that install commands should add a prerelease flag or pin a version.

Do not query package registries to check.

## Verification

Investigate thoroughly before reaching conclusions.

You are permitted and encouraged to inspect files, run the program's help
output, follow the documented steps and examples, and execute commands to
confirm or refute what the documentation claims. Don't rely on a claim being
plausible: check it. Don't install software, though: check installation
steps by reading them against the code and packaging instead.

**DO NOT EDIT ANY CODE OR TRACKED FILES, AND DO NOT COMMIT.**

Commands that generate temporary files or other artifacts are permitted.
Avoid unnecessary modifications to the working tree.

## Report

For each issue, identify the document and location, quote the problematic
text, explain the problem and its impact on a reader, and propose replacement
wording or a fix. Say how you verified it (for example, a command you ran or
the code you compared against), or that it is unverified.

Order issues by importance: first those that would mislead or block a
reader, then omissions, then minor clarity problems.

If you find no issues, say so, and mention any limits of the review.
