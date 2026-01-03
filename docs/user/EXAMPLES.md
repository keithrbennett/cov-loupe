# Examples and Recipes

[Back to main README](../index.md)

Practical examples for common tasks with cov-loupe. Examples are organized by skill level and use case.

> For brevity, these examples use `clp`, an alias to the demo fixture with partial coverage:
>
> `alias clp='cov-loupe -R docs/fixtures/demo_project'  # -R = --root`
>
> Swap `clp` for `cov-loupe` to run against your own project and resultset.
> The demo fixture is a small Rails-like project in `docs/fixtures/demo_project` with intentional coverage gaps for testing `--tracked-globs`.

## Table of Contents

- [Quick Start Examples](#quick-start-examples)
- [CLI Examples](#cli-examples)
- [Ruby Library Examples](#ruby-library-examples)
- [AI Assistant Prompts](#ai-assistant-prompts)
- [CI/CD Integration](#cicd-integration)
- [Advanced Usage](#advanced-usage)

## Quick Start Examples

### View All Coverage

```bash
# Default: show all files, best coverage first
clp

# Show files with worst coverage first
clp -o a list  # -o = --sort-order, a = ascending

# Export to JSON for processing
clp -fJ list > coverage-report.json
```

### Check Specific File

```bash
# Quick summary
clp summary app/models/order.rb

# See which lines aren't covered
clp uncovered app/controllers/orders_controller.rb

# View uncovered code with context
clp -s u -c 3 uncovered app/controllers/orders_controller.rb  # -s = --source (u = uncovered), -c = --context-lines
```

### Find Coverage Gaps

```bash
# Files with worst coverage (account for header/footer)
clp list | tail -12

# Only show files below 80%
clp -fJ list | jq '.files[] | select(.percent_covered < 80)'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].select { |f| f["percentage"] < 80 }.each do |f|
    puts JSON.pretty_generate(f)
  end
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ 'self["files"].select { |f| f["percentage"] < 80 }'

# Check specific directory
clp -g "lib/payments/**/*.rb" list  # -g = --tracked-globs
```

## CLI Examples

### Coverage Analysis

**Detailed investigation:**
```bash
# See detailed hit counts
clp detailed lib/api/client.rb

# Show full source with coverage markers
clp -s f summary lib/api/client.rb  # f = full

# Focus on uncovered areas only
clp -s u -c 5 uncovered lib/payments/refund_service.rb  # u = uncovered
```

### Working with JSON Output

In addition to the benefit of JSON encoding being human readable, it can be used in single line commands to fetch and compute values using `jq`, Ruby's JSON library, or `rexe`.
Here are some examples:

**Parse and filter:**
```bash
# Files below threshold
clp -fJ list | jq '.files[] | select(.percent_covered < 80) | {file, coverage: .percent_covered}'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].select { |f| f["percentage"] < 80 }.each do |f|
    puts JSON.pretty_generate({file: f["file"], coverage: f["percentage"]})
  end
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ '
  self["files"].select { |f| f["percentage"] < 80 }.map do |f|
    {file: f["file"], coverage: f["percentage"]}
  end
'

# Count total uncovered lines
clp -fJ totals | jq '.lines.uncovered'

# Ruby alternative:
clp -fJ totals | ruby -r json -e '
  puts JSON.parse($stdin.read)["lines"]["uncovered"]
'

# Rexe alternative:
clp -fJ totals | rexe -ij -mb -op 'self["lines"]["uncovered"]'

# Group by directory (full path)
clp -fJ list |
  jq '.files
      | map(. + {dir: (.file | split("/") | .[0:-1] | join("/"))})
      | sort_by(.dir)
      | group_by(.dir)
      | map({dir: .[0].dir, avg: (map(.percent_covered) | add / length)})'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  grouped = JSON.parse($stdin.read)["files"]
    .map { |f| f.merge("dir" => File.dirname(f["file"])) }
    .group_by { |f| f["dir"] }
    .map { |dir, files|
      avg = files.sum { |f| f["percentage"] } / files.size
      {dir: dir, avg: avg}
    }
  puts JSON.pretty_generate(grouped)
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ '
  self["files"]
    .map { |f| f.merge("dir" => File.dirname(f["file"])) }
    .group_by { |f| f["dir"] }
    .map { |dir, files|
      avg = files.sum { |f| f["percentage"] } / files.size
      {dir: dir, avg: avg}
    }
'
```

**Generate reports:**
```bash
# Create markdown table
echo "| Coverage | File |" > report.md
echo "|----------|------|" >> report.md
clp -fJ list | jq -r '.files[] | "| \(.percent_covered)% | \(.file) |"' >> report.md

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].each do |f|
    puts "| #{f["percentage"]}% | #{f["file"]} |"
  end
' >> report.md

# Rexe alternative:
clp -fJ list | rexe -ij -mb '
  self["files"].each { |f| puts "| #{f["percentage"]}% | #{f["file"]} |" }
' >> report.md

# Export for spreadsheet
clp -fJ list | jq -r '.files[] | [.file, .percent_covered] | @csv' > coverage.csv

# Ruby alternative:
clp -fJ list | ruby -r json -r csv -e '
  JSON.parse($stdin.read)["files"].each do |f|
    puts CSV.generate_line([f["file"], f["percentage"]]).chomp
  end
' > coverage.csv

# Rexe alternative:
clp -fJ list | rexe -r csv -ij -mb '
  self["files"].each { |f| puts CSV.generate_line([f["file"], f["percentage"]]).chomp }
' > coverage.csv
```

## Ruby Library Examples

### Basic Usage

```ruby
require "cov_loupe"

root = "docs/fixtures/demo_project"
model = CovLoupe::CoverageModel.new(root: root)

# Project totals
totals = model.project_totals
puts "Total files: #{totals['files']['total']}"
puts "Average coverage: #{totals['lines']['percent_covered']}%"

# Check specific file
summary = model.summary_for("app/models/order.rb")
puts "Coverage: #{summary['summary']['percent_covered']}%"

# Find uncovered lines
uncovered = model.uncovered_for("lib/payments/refund_service.rb")
puts "Uncovered lines: #{uncovered['uncovered'].join(', ')}"
```

### Filtering and Analysis

```ruby
require "cov_loupe"

root = "docs/fixtures/demo_project"
model = CovLoupe::CoverageModel.new(root: root)
list = model.list['files']

# Find files below threshold
THRESHOLD = 80.0
low_coverage = list.select { |f| f['percent_covered'] < THRESHOLD }

if low_coverage.any?
  puts "Files below #{THRESHOLD}%:"
  low_coverage.each do |file|
    puts "  #{file['file']}: #{file['percent_covered']}%"
  end
end

# Group by directory using totals command logic
dirs = %w[app lib lib/payments lib/ops/jobs].uniq
dirs.each do |dir|
  pattern = File.join(dir, '**/*.rb')
  totals = model.project_totals(tracked_globs: pattern)
  puts "#{dir}: #{totals['lines']['percent_covered'].round(2)}% (#{totals['files']['total']} files)"
end
```

### Custom Formatting

```ruby
require "cov_loupe"
require "pathname"

root = "docs/fixtures/demo_project"
model = CovLoupe::CoverageModel.new(root: root)
list = model.list['files']

# Filter to lib/payments (coverage data stores absolute paths)
lib_root = File.expand_path("lib/payments", File.expand_path(root, Dir.pwd))
lib_files = list.select { |f| f['file'].start_with?(lib_root) }

# Generate custom table
table = model.format_table(lib_files, sort_order: :ascending)
puts table

# Or create your own format
lib_files.each do |file|
  status = file['percent_covered'] >= 90 ? '✓' : '⚠'
  relative_path = Pathname.new(file['file']).relative_path_from(Pathname.pwd)
  puts "#{status} #{relative_path}: #{file['percent_covered']}%"
end
```

## AI Assistant Prompts

### Coverage Analysis

"Using cov-loupe, show me a table of all files sorted by coverage percentage."

"Using cov-loupe, find the 10 files with the lowest coverage and create a markdown report with:
1. File path
2. Current coverage %
3. Number of uncovered lines"

"Using cov-loupe, analyze the lib/payments/ directory and identify which files should be prioritized for additional testing based on coverage gaps and file complexity."

### Finding Specific Issues

"Using cov-loupe, show me the uncovered lines in app/controllers/orders_controller.rb with 5 lines of context around each uncovered block."

"Using cov-loupe, find all files in lib/payments/ with less than 80% coverage and list the specific uncovered line numbers for each."

### Test Generation

"Using cov-loupe, identify the uncovered lines in lib/ops/jobs/report_job.rb and write *meaningful* RSpec tests to cover them."

"Using cov-loupe, analyze coverage gaps in the app/controllers/ directory and generate a test plan prioritizing:
1. Public API methods
2. Error handling paths
3. Edge cases"

### Reporting

"Using cov-loupe, create a coverage report showing:
- Overall project coverage percentage
- Top 5 files with worst coverage
- Recommended next steps to improve coverage

Format as markdown."

## Test Run Integration

### Display Low Coverage Files

Add this to your `spec/spec_helper.rb` to automatically report files below a coverage threshold after each test run:

```ruby
require 'simplecov'
SimpleCov.start do
  add_filter %r{^/spec/}
  track_files 'lib/**/*.rb'  # Ensures new/untested files show up with 0%
end

# Report lowest coverage files at the end of the test run
SimpleCov.at_exit do
  SimpleCov.result.format!
  require 'cov_loupe'
  report = CovLoupe::CoverageReporter.report(threshold: 80, count: 5)
  puts report if report
end
```

This produces output like:

```
Lowest coverage files (< 80%):
    0.0%  lib/myapp/config_parser.rb
   19.3%  lib/myapp/formatters/source_formatter.rb
   24.0%  lib/myapp/model.rb
   26.0%  lib/myapp/cli.rb
   45.2%  lib/myapp/commands/base.rb
```

**Parameters:**
- `threshold:` - Coverage percentage below which files are included (default: 80)
- `count:` - Maximum number of files to show (default: 5)

**Returns:** Formatted string, or `nil` if no files are below the threshold.

## CI/CD Integration

### GitHub Actions

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
      - uses: actions/checkout@v4

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
          cov-loupe -fJ list > coverage.json

          # Verify coverage using Ruby for cross-platform compatibility
          # (Tools like jq and rexe are not guaranteed to be installed on all runners)
          ruby -r json -e '
            data = JSON.parse(File.read("coverage.json"))
            files = data["files"]
            low_cov_files = files.select { |f| f["percentage"] < 80 }

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
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-report-${{ matrix.os }}
          path: coverage.json
```

**Check for stale coverage:**
```yaml
      - name: Verify coverage is fresh
        shell: bash
        run: cov-loupe --raise-on-stale true list || exit 1
```

### GitLab CI

```yaml
test:
  image: ruby:3.4
  before_script:
    - gem install cov-loupe
  script:
    - bundle exec rspec
    - cov-loupe --raise-on-stale true list
  artifacts:
    paths:
      - coverage/
    reports:
      coverage_report:
        coverage_format: simplecov
        path: coverage/.resultset.json
```

### Custom Success Predicate

```ruby
# coverage_policy.rb
->(model) do
  list = model.list['files']

  # Must have at least 80% average coverage
  totals = model.project_totals
  return false if totals['lines']['percent_covered'] < 80.0

  # No files below 60%
  return false if list.any? { |f| f['percent_covered'] < 60.0 }

  # lib/ files must average 90%
  lib_totals = model.project_totals(tracked_globs: ['lib/**/*.rb'])
  return false if lib_totals['lines']['percent_covered'] < 90.0

  true
end
```

```bash
# Use in CI
cov-loupe validate coverage_policy.rb
```

## Advanced Usage

### Directory-Level Analysis

```ruby
require "cov_loupe"

root = "docs/fixtures/demo_project"
model = CovLoupe::CoverageModel.new(root: root)

# Calculate coverage by directory (uses the same data as `cov-loupe totals`)
patterns = %w[
  app/**/*.rb
  lib/payments/**/*.rb
  lib/ops/jobs/**/*.rb
]

results = patterns.map do |pattern|
  totals = model.project_totals(tracked_globs: pattern)

  {
    directory: pattern,
    files: totals['files']['total'],
    coverage: totals['lines']['percent_covered'].round(2),
    covered: totals['lines']['covered'],
    total: totals['lines']['total']
  }
end

# Sort by coverage ascending
results.sort_by { |r| r[:coverage] }.each do |r|
  puts "#{r[:directory]}: #{r[:coverage]}% (#{r[:files]} files)"
end
```

### Integration with Code Review

```ruby
# pr_coverage_check.rb
require "cov_loupe"
require "json"

model = CovLoupe::CoverageModel.new

# Get changed files from PR (example using git)
changed_files = `git diff --name-only origin/main`.split("\n")
changed_files.select! { |f| f.end_with?('.rb') }

puts "## Coverage Report for Changed Files\n\n"
puts "| File | Coverage | Status |"
puts "|------|----------|--------|"

changed_files.each do |file|
  begin
    summary = model.summary_for(file)
    percentage = summary['summary']['percent_covered']
    status = percentage >= 80 ? '✅' : '⚠️'
    puts "| #{file} | #{percentage}% | #{status} |"
  rescue
    puts "| #{file} | N/A | ❌ No coverage |"
  end
end
```

## Example Scripts

The `examples/` directory contains runnable scripts:

- **filter_and_table_demo.rb** - Filter and format coverage data (in `examples/` directory)
- **[success_predicates](../examples/success_predicates.md)** - Custom coverage policy examples
- **[Coverage Delta Tracking recipe in the Library API Guide](LIBRARY_API.md#coverage-delta-tracking)**

## Related Documentation

- [CLI Usage Guide](CLI_USAGE.md) - Complete command reference
- [Library API Guide](LIBRARY_API.md) - Ruby API documentation
- [MCP Integration](MCP_INTEGRATION.md) - AI assistant setup
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
