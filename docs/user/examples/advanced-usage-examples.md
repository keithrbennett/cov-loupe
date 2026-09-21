# Advanced Usage Examples

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../index.md)

## Directory-Level Analysis

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
    coverage: totals['lines']['percentage'].round(2),
    covered: totals['lines']['covered'],
    total: totals['lines']['total']
  }
end

# Sort by coverage ascending
results.sort_by { |r| r[:coverage] }.each do |r|
  puts "#{r[:directory]}: #{r[:coverage]}% (#{r[:files]} files)"
end
```

## Integration with Code Review

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
    percentage = summary['summary']['percentage']
    status = percentage >= 80 ? '✅' : '⚠️'
    puts "| #{file} | #{percentage}% | #{status} |"
  rescue
    puts "| #{file} | N/A | ❌ No coverage |"
  end
end
```
