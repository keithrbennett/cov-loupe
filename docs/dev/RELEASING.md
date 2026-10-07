# Release Process

[Back to main README](../index.md)

This document provides a checklist for releasing new versions of cov-loupe.

## Automated pre-release check

`bin/pre-release-check` is the canonical preflight interface (`rake release:check`
runs the same code; pass `rake "release:check[rerun_ci]"` for `--rerun-ci`). Run it
from a clean `main` branch after committing **and pushing** the version and release
notes; it requires a clean tree and `HEAD == origin/main`. The script looks for a successful `test.yml` run for the
exact HEAD commit and reuses it. If that commit has a run still in progress, the
script watches it. Otherwise, it starts a new run and waits for the result.
Both push and manually dispatched runs count: the current `test.yml` workflow runs
the same jobs for those events. If that changes, use `--rerun-ci` for a fresh check.

The script then builds the gem once and prints the commit SHA it was built from
and the gem's SHA256. That gem file is the single authoritative release artifact:
it must not be rebuilt after tagging, because the script verifies a clean tree,
the `main` branch, and `HEAD == origin/main` before building, and the gemspec
builds its file list from `git ls-files`. Tagging does not change the file
contents, so rebuilding after tagging adds risk without adding value. Tagging,
pushing, and `gem push` remain manual steps.

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
`VERSION` with the release version (for example, `7.1.0` or `7.1.0.pre.1`). The task
validates the version, updates `lib/cov_loupe/version.rb`, and inserts a new
`## vVERSION` heading directly below the `## Unreleased` heading in `RELEASE_NOTES.md`,
moving all existing content under it. The `## Unreleased` heading itself is left in
place as an empty placeholder for the next round of changes. It then prints the diff
command and the commit/push/check commands to run next, and reminds you of the extra
documentation work if the major version increased. Review the resulting diff
and stage the files when ready. The task stops if the version is invalid, the
`Unreleased` heading is missing or duplicated, or the release heading already exists.

### 1. Documentation Review

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

For a new major version N (for example, 8.0.0), also complete these before committing:

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
    - Work-in-progress directories (screencast/, untracked-ai-reports/, etc.)

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

- [ ] **Test installation**: Install and test the exact file the script produced
```bash
gem install ./cov-loupe-$VERSION.gem
cov-loupe --version
cov-loupe --help
# Test on actual project
cd /path/to/test/project
cov-loupe list
```
    - Uninstall or use a sandbox environment to avoid shadowing your development setup

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
    - Only pushes of a final release tag (`vX.Y.Z`, e.g. `v7.0.0`) deploy the documentation; pre-release tags such as `v7.0.0.pre.1` do not. Pull requests and pushes to `main` that change documentation-related files build the site for validation, but only final release tag pushes deploy it.

### 6. Publish Gem

- [ ] **Push the gem built by `bin/pre-release-check`**: Do not build again
    - The gem built in step 4 is the authoritative artifact; do not run
      `gem build` again after tagging
    - Optionally confirm the file hash before pushing:
```bash
sha256sum "cov-loupe-$VERSION.gem"
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
- **Minor (0.X.0)**: New features, backward compatible
- **Patch (0.0.X)**: Bug fixes, backward compatible
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

- GitHub Actions CI runs tests and Rubocop on every push and pull request
- Local pre-commit hooks run checks before commits (enable with `bin/setup-hooks`)
