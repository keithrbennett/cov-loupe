# Contributing to cov-loupe

[Back to main README](docs/index.md)

Thank you for your interest in contributing! 
This project welcomes bug reports, improvements, and suggestions that make it more useful and reliable for the Ruby community.

---

## How to Contribute

### 1. Reporting Issues
- Check existing issues before opening a new one.  
- Include clear reproduction steps, expected vs. actual results, and your Ruby version (`ruby -v`) and OS.  
- Keep discussion technical and respectful — see the [Code of Conduct](docs/code_of_conduct.md).

### 2. Submitting Changes
1. **Fork** the repository on GitHub.  
1. **Create a branch** for your work:  
   ```bash
   git checkout -b feature/my-change
   ```
1. **Install dependencies**:  
   ```bash
   bundle install
   ```
1. Make your changes, conforming to the project's coding style.
1. **Run tests** to verify your changes:  
   ```bash
   bundle exec rspec
   ```
1. **Lint the code**:  
   ```bash
   bundle exec rubocop
   ```
1. Commit changes with clear, concise messages following conventional commit style (e.g. `fix: handle missing file gracefully`).
1. **Push** your branch and open a **Pull Request** against `main`.

PRs should:
- Include or update tests for new/changed behavior.  
- Pass all existing tests and RuboCop checks.  
- Update documentation or README examples if behavior changes.

---

## Development Setup

This project requires Ruby >= 3.2 (due to the `mcp` gem dependency). Typical workflow:

```bash
git clone https://github.com/keithrbennett/cov-loupe.git
cd cov-loupe
bundle install
rspec
```

Optional tools:
- `rake` as an alternate way to run `rspec` and `rubocop`
- `exe/cov-loupe` the CLI and MCP entry point, use for end-to-end runs

---

## Documentation

This project uses [MkDocs](https://www.mkdocs.org/) with the [Material theme](https://squidfunk.github.io/mkdocs-material/) to build and serve documentation.

**Quick start:**
```bash
pip3 install -r requirements.txt
mkdocs serve  # View at http://127.0.0.1:8000
```

For detailed platform-specific installation instructions (macOS, Linux, Windows) and troubleshooting, see the [Documentation Development](docs/dev/DEVELOPMENT.md#documentation-development) section of the Development Guide

---

## Release Process (maintainer only)

1. Update version in `lib/cov_loupe/version.rb`
2. Update `RELEASE_NOTES.md`
3. Commit, tag, and push:
   ```bash
   git add -A
   git commit -m "Bump version to 1.0.0, update release notes"
   git tag -a v1.0.0 -m "v1.0.0 - brief summary of release"
   git push origin main --tags
   ```
4. Build and publish:
   ```bash
   gem build cov-loupe.gemspec
   gem push cov-loupe-#{version-string}.gem
   ```
---

## Code of Conduct

Please review and follow the [Code of Conduct](docs/code_of_conduct.md). 
Instances of unacceptable behavior may be reported through GitHub’s [Report Abuse form](https://github.com/contact/report-abuse).

---

Thank you for helping improve **cov-loupe**!
