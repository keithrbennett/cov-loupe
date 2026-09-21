# Ruby Library Examples

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../index.md)

## Basic Usage

```ruby
require "cov_loupe"

root = "docs/fixtures/demo_project"
model = CovLoupe::CoverageModel.new(root: root)

# Project totals
totals = model.project_totals
puts "Total files: #{totals['files']['total']}"
puts "Average coverage: #{totals['lines']['percentage']}%"

# Check specific file
summary = model.summary_for("app/models/order.rb")
puts "Coverage: #{summary['summary']['percentage']}%"

# Find uncovered lines
uncovered = model.uncovered_for("lib/payments/refund_service.rb")
puts "Uncovered lines: #{uncovered['uncovered'].join(', ')}"
```

## Filtering and Analysis

```ruby
require "cov_loupe"

root = "docs/fixtures/demo_project"
model = CovLoupe::CoverageModel.new(root: root)
list = model.list['files']

# Find files below threshold
THRESHOLD = 80.0
low_coverage = list.select { |f| f['percentage'] < THRESHOLD }

if low_coverage.any?
  puts "Files below #{THRESHOLD}%:"
  low_coverage.each do |file|
    puts "  #{file['file']}: #{file['percentage']}%"
  end
end

# Group by directory using totals command logic
dirs = %w[app lib lib/payments lib/ops/jobs].uniq
dirs.each do |dir|
  pattern = File.join(dir, '**/*.rb')
  totals = model.project_totals(tracked_globs: pattern)
  puts "#{dir}: #{totals['lines']['percentage'].round(2)}% (#{totals['files']['total']} files)"
end
```

## Custom Formatting

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
  status = file['percentage'] >= 90 ? '✓' : '⚠'
  relative_path = Pathname.new(file['file']).relative_path_from(Pathname.pwd)
  puts "#{status} #{relative_path}: #{file['percentage']}%"
end
```
