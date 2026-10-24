# CI/CD Integration

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../../README.md)

These examples assume your test suite runs SimpleCov 1.x, whose default HTML formatter (or its JSONFormatter) writes `coverage/coverage.json` for cov-loupe to read. See [Quick Start](../../QUICKSTART.md) to set it up.

## GitHub Actions

**Fail on low coverage (Cross-Platform):**
```yaml
name: Coverage Check

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        ruby-version: ['3.4']

    steps:
      - uses: actions/checkout@v7

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby-version }}
          bundler-cache: true

      - name: Run tests
        run: bundle exec rspec

      - name: Install cov-loupe
        run: gem install cov-loupe

      - name: Check coverage threshold
        shell: bash
        run: |
          # Generate JSON report using the full command (aliases like 'clp' are not available here)
          cov-loupe -fJ list > coverage-report.json

          # Verify coverage using Ruby for cross-platform compatibility
          # (Tools like jq and rexe are not guaranteed to be installed on all runners)
          ruby -r json -e '
            data = JSON.parse(File.read("coverage-report.json"))
            files = data["files"]
            low_cov_files = files.select { |f| f["percentage"] && f["percentage"] < 80 }

            if low_cov_files.any?
              puts "❌ #{low_cov_files.count} files below 80% coverage:"
              low_cov_files.each do |f|
                puts "  #{f["percentage"]}% #{f["file"]}"
              end
              exit 1
            end
            puts "✓ All files meet coverage threshold"
          '

      - name: Upload coverage report
        # Saves the coverage file as an artifact so you can download/inspect it 
        # from the GitHub Actions run summary page.
        uses: actions/upload-artifact@v7
        if: always()
        with:
          name: coverage-report-${{ matrix.os }}
          path: coverage-report.json
```

**Check for stale coverage:**
```yaml
      - name: Verify coverage is fresh
        shell: bash
        run: cov-loupe --raise-on-stale true list || exit 1
```

## GitLab CI

```yaml
test:
  image: ruby:3.4
  before_script:
    - bundle install
    - gem install cov-loupe
  script:
    - bundle exec rspec
    - cov-loupe --raise-on-stale true list
  artifacts:
    paths:
      - coverage/
```

## Custom Success Predicate

```ruby
# coverage_policy.rb
->(model) do
  # percentage is nil when nothing can be measured. Totals use `to_f` so that fails the check;
  # a file with no coverable lines has nothing to cover, so the per-file check skips it.
  list = model.list['files']

  # Must have at least 80% overall line coverage
  return false if model.project_totals['lines']['percentage'].to_f < 80.0

  # No files below 60%
  return false if list.any? { |f| f['percentage'] && f['percentage'] < 60.0 }

  # lib/ files must have at least 90% overall line coverage
  lib_totals = model.project_totals(tracked_globs: ['lib/**/*.rb'])
  return false if lib_totals['lines']['percentage'].to_f < 90.0

  true
end
```

```bash
# Use in CI
cov-loupe validate coverage_policy.rb
```
