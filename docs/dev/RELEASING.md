# Release Process

[Back to main README](../../README.md)

This document provides a checklist for releasing new versions of cov-loupe.

## Automated pre-release check

`bin/pre-release-check` is the canonical preflight script. (`rake release:check`
runs the same code; use `rake "release:check[rerun_ci]"` for `--rerun-ci`.) Run it
on `main` after committing **and pushing** the version and release notes: it
requires a clean tree and `HEAD == origin/main`.

The script first checks CI for the exact HEAD commit:

- If a `test.yml` run for that commit succeeded, it reuses the result.
- If a run is still in progress, it watches it.
- Otherwise, it starts a new run and waits for the result.

Both push and manually dispatched runs count, because the current `test.yml`
workflow runs the same jobs for both events. If that changes, use `--rerun-ci` for
a fresh check.

The script then builds the gem once and prints the commit SHA it was built from
and the gem's SHA256. That gem file is the release artifact; do not rebuild it
after tagging. The script builds only after verifying a clean tree, the `main`
branch, and `HEAD == origin/main`, and the gemspec takes its file list from
`git ls-files`, so the gem already matches the commit you will tag. A rebuild
could only add risk. Tagging, pushing, and `gem push` remain manual steps.

Use `bin/pre-release-check --rerun-ci` to start a fresh run even when HEAD already
passed. This is useful when CI configuration or external dependencies need a new
check. The script waits up to about five minutes for a dispatched run to appear.

The check requires GitHub CLI (`gh`) installed and authenticated for this repository.
Run `gh auth status` to verify the login, or `gh auth login` to authenticate. The
account or token needs Actions read access to list and watch runs. Starting a new
run, including with `--rerun-ci`, also needs Actions write access. The installed
`gh` must support `gh run list --commit`; check with `gh run list --help`.

## Pre-Release Checklist

Before preparing a release, run `bundle exec rake "release:bump[VERSION]"`, replacing
`VERSION` with the release version (for example, `7.1.0` or `7.1.0.pre.1`). The task:

- validates the version and updates `lib/cov_loupe/version.rb`
- inserts a `## vVERSION` heading directly below `## Unreleased` in `RELEASE_NOTES.md`,
  so the existing unreleased notes move under the new heading, and leaves `## Unreleased`
  in place, empty, for the next round of changes
- prints the diff command and the commit, push, and check commands to run next
- for a major release (the major version increased, or the version is a stable `X.0.0`,
  as when finalizing `X.0.0.pre.N`), reminds you of the extra documentation work

It stops if the version is invalid, the `Unreleased` heading is missing or duplicated,
or the release heading already exists. Review the resulting diff and stage the files
when ready.

### 1. Documentation Review

- [ ] **Release review prompt** (optional): [`dev/prompts/review/release-review.md`](https://github.com/keithrbennett/cov-loupe/blob/main/dev/prompts/review/release-review.md) is a pre-release review prompt for AI agents

- [ ] **RELEASE_NOTES.md**: Review release notes after running `release:bump`
    - For major releases: Ensure a `### Breaking` section lists every breaking change (see [Major releases](#major-releases))
    - Verify new features and bug fixes are listed

- [ ] **README.md**: Verify examples and feature list are current

- [ ] **Documentation**: Ensure all docs in `docs/` are up to date

### 2. Code Quality

- [ ] **Tests**: All tests passing (`bundle exec rspec`)
    - Verify via git hooks or run manually
    - Check coverage is still excellent (>95%)

- [ ] **Linting**: No Rubocop violations (`bundle exec rubocop`)
    - Verify via git hooks or run manually

- [ ] **Version**: Confirm `lib/cov_loupe/version.rb` has the release version (set by `release:bump`)
    - Stable releases must not have a `.pre.X` suffix

- [ ] **Payload schema**: If a structured payload shape changed incompatibly since the last release, increment `CovLoupe::SCHEMA_VERSION`, copy the current `lib/cov_loupe/schemas/vN/` directory to the new version and edit the new copy, update the pinned value in `spec/cov_loupe/version_spec.rb`, and document the change in `RELEASE_NOTES.md` and the migration guide
    - Confirm earlier schema directories are unchanged since the last release (for example, `git --no-pager diff <last-tag> -- lib/cov_loupe/schemas/v1/`)

### Major releases

For a new major version N (for example, 8.0.0), also complete these **before** the
commit and push in step 4; neither `release:bump` nor `bin/pre-release-check` verifies them:

- [ ] Create `docs/user/migrations/MIGRATING_TO_V<N>.md` with migration examples for every
  breaking change in `RELEASE_NOTES.md`
- [ ] Add the guide to the lists in `docs/user/migrations/README.md`, `README.md`,
  `docs/user/README.md` (the "v2 through vN" text), and `docs/user/INSTALLATION.md`
- [ ] Add the guide to the navigation in `mkdocs.yml`
- [ ] Search the docs for stale version references (for example, `rg 'v<N-1>' docs README.md`)

### 3. Cleanup

- [ ] **Untracked files**: Review `git status` for files that should be:
    - Added to `.gitignore` (temp files, local experiments, AI reports)
    - Committed (valuable documentation or examples)
    - Deleted (obsolete files)

- [ ] **Temporary files**: Remove or ignore:
    - `*.txt` files (r.txt, rubocop.txt, todo.txt, etc.)
    - Experimental config files (`.rubocop.yml.new`, etc.)
    - Local notes (CODING_AGENT_NOTES.md, architecture_insights.md, etc.)
    - Work-in-progress directories (screencast/, etc.)

### 4. Build Verification

Set the release version once; later commands in this document use it:

```bash
VERSION=7.1.0   # the version you passed to release:bump
```

- [ ] **Commit and push changes**: Commit the version bump, release notes, and any docs
```bash
git add lib/cov_loupe/version.rb RELEASE_NOTES.md   # plus any docs you changed
git commit -m "Release version $VERSION"
git push origin main
```
    - This must happen before `bin/pre-release-check`, which requires a clean tree
      and `HEAD == origin/main`

- [ ] **Run pre-release check**: Build the release gem with the script
```bash
bin/pre-release-check
```
    - Note the build commit SHA and SHA256 it prints
    - The `cov-loupe-$VERSION.gem` file it produces is the authoritative release artifact

- [ ] **Test installation**: Smoke-test the exact file the script produced
```bash
bundle exec rake release:smoke_test
```
    - Installs `cov-loupe-$VERSION.gem` into a temporary gem directory, with `GEM_PATH`
      limited to that directory. The directory holds only the gem and copies of the
      installed gems its declared runtime dependencies resolve to, so a dependency missing
      from the gemspec is not found (unless a declared dependency also depends on it, or it
      is a default gem such as `json`, which Ruby always provides). Nothing is downloaded,
      so the dependencies must already be installed (`bundle install`).
    - It then runs the installed executable: `--version` (against the version the gem
      declares), `--help`, `--path-for docs-local` (to confirm it runs from the installed gem,
      not this checkout, and that its README is packaged), `totals` against the demo
      project's coverage data the gem ships, and a `help` call to the MCP server (which loads
      the `mcp` dependency). Nothing outside the temporary directory changes.
    - Without an argument it tests `cov-loupe-$VERSION.gem` in the repository root, or else
      in `pkg/` (from `rake build`). To test another file:
      `bundle exec rake "release:smoke_test[path/to/cov-loupe-$VERSION.gem]"`.
    - Optionally also try it on a real project. This installs into your default gem
      directory, so uninstall it afterward, or use a scratch `GEM_HOME`, to avoid shadowing
      your development setup:
```bash
gem install ./cov-loupe-$VERSION.gem
(cd /path/to/test/project && cov-loupe list)
gem uninstall cov-loupe -v "$VERSION"
```

### 5. Git Release

- [ ] **Create tag**: Tag the release at the commit the gem was built from
```bash
git tag -a "v$VERSION" -m "Version $VERSION" <build-commit-sha>
```
    - Use the exact SHA printed by `bin/pre-release-check` so the tag cannot
      drift to a different commit if HEAD moves

- [ ] **Push**: Push commits and tags
```bash
git push origin main --follow-tags
```
    - Pushing a final release tag (`vX.Y.Z`, e.g. `v7.0.0`) deploys the documentation; pre-release tags such as `v7.0.0.pre.1` do not. See [Publishing Documentation](DOC_SERVER.md#publishing-documentation).

### 6. Publish Gem

- [ ] **Push the gem built by `bin/pre-release-check`**: Do not build again
    - The gem built in step 4 is the authoritative artifact; do not run
      `gem build` again after tagging
    - Optionally confirm the file hash before pushing:
```bash
sha256sum "cov-loupe-$VERSION.gem"   # macOS: shasum -a 256 "cov-loupe-$VERSION.gem"
```
    - Compare against the SHA256 printed by the script

- [ ] **Push to RubyGems**: Publish the exact file the script built
```bash
gem push "cov-loupe-$VERSION.gem"
```

- [ ] **Verify publication**: Check gem appears on RubyGems.org
    - Visit https://rubygems.org/gems/cov-loupe
    - Verify new version is listed
    - Check that documentation links work

### 7. GitHub Release

- [ ] **Create GitHub release**: Go to https://github.com/keithrbennett/cov-loupe/releases/new
    - Select the tag you just pushed
    - Title: `Version <VERSION>`
    - Description: Copy relevant sections from RELEASE_NOTES.md
    - Attach the `.gem` file (optional)

### 8. Post-Release

- [ ] **Announcement**: Consider announcing on:
    - Ruby Weekly
    - Reddit (r/ruby)
    - Slack/Discord communities
    - Social media

- [ ] **Update dependencies**: For projects using this gem
    - Update your own projects to use new version
    - Test integration

- [ ] **Prepare for next release**:
    - `release:bump` already leaves an empty `## Unreleased` section in RELEASE_NOTES.md
    - Consider bumping to next pre-release version if starting new development cycle

## Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **Major (X.0.0)**: Breaking changes
- **Minor (x.Y.0)**: New features, backward compatible
- **Patch (x.y.Z)**: Bug fixes, backward compatible
- **Pre-release (X.Y.Z.pre.N)**: Development versions

## Rollback Procedure

If a critical issue is discovered after release:

1. **Yank the gem** (removes from RubyGems but preserves install history):
```bash
gem yank cov-loupe -v "$VERSION"
```

2. **Fix the issue** in a new patch version

3. **Release the fixed version** following this checklist

4. **Communicate**: Update GitHub release notes and announce the issue + fix

## Notes

- GitHub Actions CI runs tests and Rubocop on every push to `main` and every pull request against `main`
- Local pre-commit hooks run checks before commits (enable with `bin/setup-hooks`)
