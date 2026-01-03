# Library API Guide

[Back to main README](../index.md)

Use this gem programmatically to inspect coverage without running the CLI or MCP server. The primary entry point is `CovLoupe::CoverageModel`.

## Table of Contents

- [Quick Start](#quick-start)
- [Method Reference](#method-reference)
- [Return Types](#return-types)
- [Error Handling](#error-handling)
- [Advanced Recipes](#advanced-recipes)

## Quick Start

```ruby
require "cov_loupe"

# Defaults (omit args; shown here with comments):
# - root: "."
# - resultset: resolved from common paths under root
# - raise_on_stale: false (don't raise on stale data)
# - tracked_globs: nil (no project-level file-set checks)
model = CovLoupe::CoverageModel.new

# Custom configuration (non-default values):
model = CovLoupe::CoverageModel.new(
  root: File.join(Dir.home, 'project'),          # non-default project root
  resultset: "build/coverage",                   # file or directory containing .resultset.json
  raise_on_stale: true,                          # enable strict staleness checks (raise on stale)
  tracked_globs: ["lib/cov_loupe/tools/**/*.rb"] # for 'list' staleness: flag new/missing files
)

# List all files with coverage summary
list_result = model.list
files = list_result['files']
# Per-file queries

target = 'lib/cov_loupe/base_tool.rb'
summary = model.summary_for(target)
uncovered = model.uncovered_for(target)
detailed = model.detailed_for(target)
raw = model.raw_for(target)
```

## Method Reference

### `list(sort_order: :descending, raise_on_stale: nil, tracked_globs: nil)`

Returns coverage summary for all files in the resultset.

**Parameters:**
- `sort_order` (Symbol, optional): `:descending` (default) or `:ascending` by coverage percentage
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.
- `tracked_globs` (Array<String>, optional): Patterns to filter files (also used for staleness checks)

**Returns:** `Hash` - See [list return type](#list)

**Example:**
```ruby
list_result = model.list
files = list_result['files']
# => [ { 'file' => '/abs/path/lib/foo.rb', 'covered' => 12, 'total' => 14, 'percentage' => 85.71, 'stale' => false }, ... ]

# Get worst coverage first
worst_files = model.list(sort_order: :ascending)['files'].first(10)

# Force staleness check
model.list(raise_on_stale: true)
```

### `summary_for(path)`

Returns coverage summary for a specific file.

**Parameters:**
- `path` (String): File path (absolute, relative to root, or basename)

**Returns:** `Hash` - See [summary_for return type](#summary_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
summary = model.summary_for(target)
# => { 'file' => '/abs/.../lib/foo.rb', 'summary' => {'covered'=>12, 'total'=>14, 'percentage'=>85.71} }
```

### `uncovered_for(path)`

Returns list of uncovered line numbers for a specific file.

**Parameters:**
- `path` (String): File path (absolute, relative to root, or basename)

**Returns:** `Hash` - See [uncovered_for return type](#uncovered_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
uncovered = model.uncovered_for("lib/foo.rb")
# => { 'file' => '/abs/.../lib/foo.rb', 'uncovered' => [5, 9, 12], 'summary' => { ... } }
```

### `detailed_for(path)`

Returns per-line coverage details with hit counts.

**Parameters:**
- `path` (String): File path (absolute, relative to root, or basename)

**Returns:** `Hash` - See [detailed_for return type](#detailed_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
detailed = model.detailed_for("lib/foo.rb")
# => { 'file' => '/abs/.../lib/foo.rb', 'lines' => [{'line' => 1, 'hits' => 1, 'covered' => true}, ...], 'summary' => { ... } }
```

### `raw_for(path)`

Returns raw SimpleCov lines array for a specific file.

**Parameters:**
- `path` (String): File path (absolute, relative to root, or basename)

**Returns:** `Hash` - See [raw_for return type](#raw_for)

**Raises:** `CovLoupe::FileError` if file not in coverage data

**Example:**
```ruby
raw = model.raw_for("lib/foo.rb")
# => { 'file' => '/abs/.../lib/foo.rb', 'lines' => [nil, 1, 0, 3, ...] }
```

### `format_table(rows = nil, sort_order: :descending, raise_on_stale: nil, tracked_globs: nil)`

Generates formatted ASCII table string.

**Parameters:**
- `rows` (Array<Hash>, optional): Custom row data; defaults to `list`
- `sort_order` (Symbol, optional): `:descending` (default) or `:ascending`
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.
- `tracked_globs` (Array<String>, optional): Patterns to filter files.

**Returns:** `String` - Formatted table with Unicode borders

**Example:**
```ruby
# Default: all files
table = model.format_table
puts table

# Custom rows
lib_files = model.list['files'].select { |f| f['file'].include?('/lib/') }
lib_table = model.format_table(lib_files, sort_order: :descending)
puts lib_table
```

### `project_totals(tracked_globs: nil, raise_on_stale: nil)`

Returns aggregated coverage totals across all files.

**Parameters:**
- `tracked_globs` (Array<String> or String, optional): Glob patterns to filter files
- `raise_on_stale` (Boolean, optional): Whether to raise error if project is stale. Defaults to model setting.

**Returns:** `Hash` - See [project_totals return type](#project_totals)

**Example:**
```ruby
totals = model.project_totals
# => {
#      'lines' => { 'total' => 123, 'covered' => 100, 'uncovered' => 23, 'percent_covered' => 81.3 },
#      'tracking' => { 'enabled' => true, 'globs' => ['lib/**/*.rb'] },
#      'files' => { 'total' => 4, 'with_coverage' => { 'total' => 4, 'ok' => 4, 'stale' => { ... } } }
#    }

# Filter to specific directory
lib_totals = model.project_totals(tracked_globs: 'lib/**/*.rb')
```

When `raise_on_stale: true` is set, the method raises on stale coverage instead of returning totals. Otherwise, totals exclude stale files (`M`, `T`, `L`, `E`) from line counts and report stale breakdowns under `files['with_coverage']['stale']`.

### `relativize(data)`

Converts absolute file paths in coverage data to relative paths from project root.

**Parameters:**
- `data` (Hash or Array<Hash>): Coverage data with absolute file paths

**Returns:** `Hash` or `Array<Hash>` - Same structure with relative paths

**Example:**
```ruby
summary = model.summary_for('lib/cov_loupe/model.rb')
# => { 'file' => '/path/to/project/lib/cov_loupe/model.rb', ... }

relative_summary = model.relativize(summary)
# => { 'file' => 'lib/cov_loupe/model.rb', ... }

# Works with arrays too
list_result = model.list
files = list_result['files']
relative_files = model.relativize(files)
```

## Return Types

### `list`

Returns `Hash` with file data and staleness metadata:

```ruby
{
  'files' => [
    {
      'file' => String,       # Absolute file path
      'covered' => Integer,   # Number of covered lines
      'total' => Integer,     # Total relevant lines
      'percent_covered' => Float,  # Coverage percentage (0.00-100.00)
      'stale' => false | String  # Staleness indicator: false, 'E', 'M', 'T', or 'L'
    }
  ],
  'skipped_files' => Array<String>,        # Files skipped due to coverage errors
  'missing_tracked_files' => Array<String>,# Tracked files missing from coverage
  'newer_files' => Array<String>,          # Files newer than coverage
  'deleted_files' => Array<String>,        # Coverage entries for deleted files
  'length_mismatch_files' => Array<String>,# Files whose line counts differ from coverage
  'unreadable_files' => Array<String>      # Files that could not be read
}
```

### `summary_for`

Returns `Hash`:

```ruby
{
  'file' => String,       # Absolute file path
  'summary' => {
    'covered' => Integer, # Number of covered lines
    'total' => Integer,   # Total relevant lines
    'percent_covered' => Float        # Coverage percentage (0.00-100.00)
  }
}
```
`without_coverage` is only present when tracking is enabled (tracked globs provided).

### `uncovered_for`

Returns `Hash`:

```ruby
{
  'file' => String,       # Absolute file path
  'uncovered' => Array<Integer>,  # Line numbers that are not covered
  'summary' => {
    'covered' => Integer,
    'total' => Integer,
    'percent_covered' => Float
  }
}
```

### `detailed_for`

Returns `Hash`:

```ruby
{
  'file' => String,       # Absolute file path
  'lines' => Array<Hash>, # Per-line coverage details
  'summary' => {
    'covered' => Integer,
    'total' => Integer,
    'percent_covered' => Float
  }
}
```

Each element in `lines` array:
```ruby
{
  'line' => Integer,    # Line number (1-indexed)
  'hits' => Integer,    # Execution count (0 means not covered)
  'covered' => Boolean  # true if hits > 0
}
```

### `raw_for`

Returns `Hash`:

```ruby
{
  'file' => String,              # Absolute file path
  'lines' => Array<Integer | nil>   # SimpleCov lines array (nil = irrelevant, 0 = uncovered, >0 = hit count)
}
```

### `project_totals`

Returns `Hash`:

```ruby
{
  'lines' => {
    'total' => Integer,            # Total relevant lines across all files
    'covered' => Integer,          # Total covered lines
    'uncovered' => Integer,        # Total uncovered lines
    'percent_covered' => Float     # Overall percent covered
  },
  'tracking' => {
    'enabled' => Boolean,          # Whether tracked_globs are active
    'globs' => Array<String>       # Active tracked globs (empty when disabled)
  },
  'files' => {
    'total' => Integer,          # Total number of files (with + without coverage)
    'with_coverage' => {
      'total' => Integer,        # Files with coverage entries
      'ok' => Integer,           # Fresh coverage entries
      'stale' => {
        'total' => Integer,      # Stale coverage entries
        'by_type' => {
          'missing_from_disk' => Integer,
          'newer' => Integer,
          'length_mismatch' => Integer,
          'unreadable' => Integer
        }
      }
    },
    'without_coverage' => {
      'total' => Integer,        # Tracked files missing coverage entries
      'by_type' => {
        'missing_from_coverage' => Integer,
        'unreadable' => Integer,
        'skipped' => Integer
      }
    }
  }
}
```

## Error Handling

### Exception Types

The library raises these custom exceptions:

- **`CovLoupe::ResultsetNotFoundError`** - Coverage data file not found
- **`CovLoupe::FileError`** - Requested file not in coverage data
- **`CovLoupe::CoverageDataStaleError`** - Coverage data is stale (only when `raise_on_stale: true`)
- **`CovLoupe::CoverageDataError`** - Invalid coverage data format or structure

All exceptions inherit from `CovLoupe::Error`.

### Basic Error Handling

```ruby
require "cov_loupe"

begin
  model = CovLoupe::CoverageModel.new
  summary = model.summary_for("lib/foo.rb")
  puts "Coverage: #{summary['summary']['percent_covered']}%"
rescue CovLoupe::FileError => e
  puts "File not in coverage data: #{e.message}"
rescue CovLoupe::ResultsetNotFoundError => e
  puts "Coverage data not found: #{e.message}"
  puts "Run your tests first: bundle exec rspec"
rescue CovLoupe::Error => e
  puts "Coverage error: #{e.message}"
end
```

### Handling Stale Coverage

```ruby
# Option 1: Check staleness without raising
model = CovLoupe::CoverageModel.new(raise_on_stale: false)
files = model.list['files']

stale_files = files.select { |f| f['stale'] }
if stale_files.any?
  puts "Warning: #{stale_files.length} files have stale coverage"
  stale_files.each do |f|
    puts "  #{f['file']}: #{f['stale']}"
  end
end

# Option 2: Raise on staleness
begin
  model = CovLoupe::CoverageModel.new(raise_on_stale: true)
  files = model.list['files']
rescue CovLoupe::CoverageDataStaleError => e
  puts "Stale coverage detected: #{e.message}"
  puts "Re-run tests: bundle exec rspec"
  exit 1
end
```

### Graceful Degradation

```ruby
# Try multiple file paths
def find_coverage(model, possible_paths)
  possible_paths.each do |path|
    begin
      return model.summary_for(path)
    rescue CovLoupe::FileError
      next
    end
  end
  nil
end

summary = find_coverage(model, [
  "lib/services/auth_service.rb",
  "app/services/auth_service.rb",
  "services/auth_service.rb"
])

if summary
  puts "Coverage: #{summary['summary']['percent_covered']}%"
else
  puts "File not found in coverage data"
end
```

## Advanced Recipes

### Batch File Analysis

```ruby
require "cov_loupe"

model = CovLoupe::CoverageModel.new

# Analyze multiple files efficiently
files_to_check = [
  "lib/auth_service.rb",
  "lib/payment_processor.rb",
  "lib/user_manager.rb"
]

results = files_to_check.map do |path|
  begin
    summary = model.summary_for(path)
    {
      file: path,
      coverage: summary['summary']['percent_covered'],
      status: summary['summary']['percent_covered'] >= 80 ? :ok : :low
    }
  rescue CovLoupe::FileError
    {
      file: path,
      coverage: nil,
      status: :missing
    }
  end
end

# Report
results.each do |r|
  status_icon = { ok: '✓', low: '⚠', missing: '✗' }[r[:status]]
  puts "#{status_icon} #{r[:file]}: #{r[:coverage] || 'N/A'}%"
end
```

### Coverage Threshold Validation

```ruby
require "cov_loupe"

class CoverageValidator
  THRESHOLDS = {
    'lib/api/' => 90.0,         # API layer needs 90%+
    'app/models/' => 85.0,      # Models need 85%+
    'app/controllers/' => 75.0, # Controllers need 75%+
  }

  def initialize(model)
    @model = model
  end

  def validate!
    files = @model.list['files']
    failures = []

    files.each do |file|
      threshold = threshold_for(file['file'])
      next unless threshold

      if file['percent_covered'] < threshold
        failures << {
          file: file['file'],
          actual: file['percent_covered'],
          required: threshold,
          gap: threshold - file['percent_covered']
        }
      end
    end

    if failures.any?
      puts "❌ #{failures.length} files below coverage threshold:"
      failures.sort_by { |f| -f[:gap] }.each do |f|
        puts "  #{f[:file]}: #{f[:actual]}% (need #{f[:required]}%)"
      end
      exit 1
    else
      puts "✓ All files meet coverage thresholds"
    end
  end

  private

  def threshold_for(path)
    THRESHOLDS.each do |prefix, threshold|
      return threshold if path.include?(prefix)
    end
    nil
  end
end

model = CovLoupe::CoverageModel.new
validator = CoverageValidator.new(model)
validator.validate!
```

### Directory-Level Aggregation

```ruby
require "cov_loupe"

model = CovLoupe::CoverageModel.new

# Calculate coverage by directory using the totals API
patterns = %w[lib/cov_loupe/tools/**/*.rb lib/cov_loupe/commands/**/*.rb lib/cov_loupe/presenters/**/*.rb]

directory_stats = patterns.map do |pattern|
  totals = model.project_totals(tracked_globs: pattern)

  {
    directory: pattern,
    files: totals['files']['total'],
    coverage: totals['lines']['percent_covered'].round(2),
    covered: totals['lines']['covered'],
    total: totals['lines']['total']
  }
end

# Display sorted by coverage
directory_stats.sort_by { |s| s[:coverage] }.each do |stat|
  puts "#{stat[:directory]}: #{stat[:coverage]}% (#{stat[:files]} files)"
end
```

### Coverage Delta Tracking

```ruby
require "cov_loupe"
require "json"

class CoverageDeltaTracker
  def initialize(baseline_path: "coverage_baseline.json")
    @baseline_path = baseline_path
    @model = CovLoupe::CoverageModel.new
  end

  def save_baseline
    current = @model.list['files']
    File.write(@baseline_path, JSON.pretty_generate(current))
    puts "Saved coverage baseline (#{current.length} files)"
  end

  def compare
    unless File.exist?(@baseline_path)
      puts "No baseline found. Run save_baseline first."
      return
    end

    baseline = JSON.parse(File.read(@baseline_path))
    current = @model.list['files']

    improved = []
    regressed = []

    current.each do |file|
      baseline_file = baseline.find { |f| f['file'] == file['file'] }
      next unless baseline_file

      delta = file['percent_covered'] - baseline_file['percent_covered']

      if delta > 0.1
        improved << {
          file: file['file'],
          before: baseline_file['percent_covered'],
          after: file['percent_covered'],
          delta: delta
        }
      elsif delta < -0.1
        regressed << {
          file: file['file'],
          before: baseline_file['percent_covered'],
          after: file['percent_covered'],
          delta: delta
        }
      end
    end

    if improved.any?
      puts "\n✓ Coverage Improvements:"
      improved.sort_by { |f| -f[:delta] }.each do |f|
        puts "  #{f[:file]}: #{f[:before]}% → #{f[:after]}% (+#{f[:delta].round(2)}%)"
      end
    end

    if regressed.any?
      puts "\n⚠ Coverage Regressions:"
      regressed.sort_by { |f| f[:delta] }.each do |f|
        puts "  #{f[:file]}: #{f[:before]}% → #{f[:after]}% (#{f[:delta].round(2)}%)"
      end
    end

    if improved.empty? && regressed.empty?
      puts "No significant coverage changes"
    end
  end
end

# Usage
tracker = CoverageDeltaTracker.new
tracker.save_baseline  # Run before making changes
# ... make code changes and re-run tests ...
tracker.compare        # See what changed
```

### Custom Reporting

```ruby
require "cov_loupe"

class CoverageReporter
  def initialize(model)
    @model = model
  end

  def generate_markdown_report(output_path)
    files = @model.list['files']
    totals = @model.project_totals

    # Overall stats
    overall_percentage = totals['lines']['percent_covered']
    total_lines = totals['lines']['total']
    covered_lines = totals['lines']['covered']
    total_files = totals['files']['total']

    # Files below threshold
    threshold = 80.0
    low_coverage = files.select { |file| file['percent_covered'] < threshold }

    # Build low coverage table
    low_coverage_section = if low_coverage.any?
      rows = low_coverage.sort_by { |file| file['percent_covered'] }.map do |file|
        uncovered = @model.uncovered_for(file['file'])
        missing_count = uncovered['uncovered'].length
        "| #{file['file']} | #{file['percent_covered']}% | #{missing_count} |"
      end.join("\n")

      <<~LOW_COVERAGE_TABLE

        ## Files Below #{threshold}% Coverage

        | File | Coverage | Missing Lines |
        |------|----------|---------------|
        #{rows}
      LOW_COVERAGE_TABLE
    else
      ""
    end

    # Build top performers table
    top_rows = files.sort_by { |file| -file['percent_covered'] }.take(10).map do |file|
      "| #{file['file']} | #{file['percent_covered']}% |"
    end.join("\n")

    # Generate report
    report = <<~COVERAGE_REPORT
      # Coverage Report

      Generated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}

      ## Overall Coverage: #{overall_percentage}%

      - Total Files: #{total_files}
      - Total Lines: #{total_lines}
      - Covered Lines: #{covered_lines}
      #{low_coverage_section}
      ## Top 10 Best Covered Files

      | File | Coverage |
      |------|----------|
      #{top_rows}
    COVERAGE_REPORT

    File.write(output_path, report)
    puts "Report saved to #{output_path}"
  end
end

model = CovLoupe::CoverageModel.new
reporter = CoverageReporter.new(model)
reporter.generate_markdown_report("coverage_report.md")
```

## Staleness Detection

The `list` method returns a `'stale'` field for each file with one of these values:

- `false` - Coverage data is current
- `'M'` - **Missing**: File no longer exists on disk
- `'T'` - **Timestamp**: File modified more recently than coverage data
- `'L'` - **Length**: Source file line count differs from coverage data
- `'E'` - **Error**: Staleness check failed

**Note:** Per-file methods (`summary_for`, `uncovered_for`, `detailed_for`, `raw_for`) do not include staleness information in their return values. To check staleness for individual files, use `list` and filter the results.

When `raise_on_stale: true` is enabled in `CoverageModel.new`, the model will raise `CovLoupe::CoverageDataStaleError` exceptions when stale files are detected during method calls.

## Related Documentation

- [Examples](EXAMPLES.md) - Practical cookbook-style examples
- [CLI Usage](CLI_USAGE.md) - Command-line interface reference
- [Error Handling](ERROR_HANDLING.md) - Detailed error handling documentation
- [MCP Integration](MCP_INTEGRATION.md) - AI assistant integration
