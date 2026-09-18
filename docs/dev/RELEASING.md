# Release Process

[Back to main README](../index.md)

This document provides a checklist for releasing new versions of cov-loupe.

## Pre-Release Checklist

### 1. Documentation Review

- [ ] **RELEASE_NOTES.md**: Update version header
    - Update the version section header to final version (e.g., `## v#{version}`)
    - For major releases: Ensure all breaking changes are documented with migration examples
    - Verify new features and bug fixes are listed

- [ ] **README.md**: Verify examples and feature list are current

- [ ] **Documentation**: Ensure all docs in `docs/` are up to date

### 2. Code Quality

- [ ] **Tests**: All tests passing (`bundle exec rspec`)
    - Verify via git hooks or run manually
    - Check coverage is still excellent (>95%)

- [ ] **Linting**: No Rubocop violations (`bundle exec rubocop`)
    - Verify via git hooks or run manually

- [ ] **Version**: Update `lib/cov_loupe/version.rb` to release version
    - Remove `.pre.X` suffix for stable releases

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

- [ ] **Build gem**: Verify gem builds without errors
```bash
gem build cov-loupe.gemspec
```

- [ ] **Test installation**: Install and test locally
```bash
gem install cov-loupe-*.gem
cov-loupe --version
cov-loupe --help
# Test on actual project
cd /path/to/test/project
cov-loupe list
```

### 5. Git Release

- [ ] **Commit changes**: Commit version bump and RELEASE_NOTES.md updates
```bash
git add lib/cov_loupe/version.rb RELEASE_NOTES.md
git commit -m "Release version #{version}"
```

- [ ] **Create tag**: Tag the release
```bash
git tag -a v#{version} -m "Version #{version}"
```

- [ ] **Push**: Push commits and tags
```bash
git push origin main --follow-tags
```
    - Only pushes with a version tag matching `v[0-9]*` deploy the documentation. Pull requests and pushes to `main` that change documentation-related files build the site for validation, but only matching version-tag pushes deploy it.

### 6. Publish Gem

- [ ] **Build final gem**: Build from tagged version
```bash
gem build cov-loupe.gemspec
```

- [ ] **Push to RubyGems**: Publish the gem
```bash
gem push cov-loupe-#{version}.gem
```

- [ ] **Verify publication**: Check gem appears on RubyGems.org
    - Visit https://rubygems.org/gems/cov-loupe
    - Verify new version is listed
    - Check that documentation links work

### 7. GitHub Release

- [ ] **Create GitHub release**: Go to https://github.com/keithrbennett/cov-loupe/releases/new
    - Select the tag you just pushed
    - Title: `Version #{version}`
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
    - Optionally create a new section in RELEASE_NOTES.md for next version
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
gem yank cov-loupe -v #{version}
```

2. **Fix the issue** in a new patch version

3. **Release the fixed version** following this checklist

4. **Communicate**: Update GitHub release notes and announce the issue + fix

## Notes

- GitHub Actions runs tests and Rubocop on every commit (via hooks)
- Pre-commit hooks ensure code quality before commits
