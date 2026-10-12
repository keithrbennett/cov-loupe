# cov-loupe Library Usage Examples
=============================================

## 1. Full Coverage Table
```
┌────────────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                           │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ /home/kbennett/code/cov-loupe/lib/bar.rb   │   33.33% │         1 │       3 │   !   │
│ /home/kbennett/code/cov-loupe/lib/foo.rb   │   66.66% │         2 │       3 │   !   │
└────────────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 2, ok 0, stale 2
```

## 2. Filter by Directory (lib/ only)
```ruby
# Filter files by directory (e.g., only show files in lib/)
files_data = model.list
lib_files = files_data.select { |file| file["file"].include?("/lib/") }
lib_files_table = model.format_table(lib_files)
# => formatted table showing only files from lib/ directory
```

Result:
```
┌────────────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                           │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ /home/kbennett/code/cov-loupe/lib/bar.rb   │   33.33% │         1 │       3 │   !   │
│ /home/kbennett/code/cov-loupe/lib/foo.rb   │   66.66% │         2 │       3 │   !   │
└────────────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 2, ok 0, stale 2
```

  ## 3. Filter by Pattern (files with specific naming)
  ```ruby
  # Filter by pattern (e.g., only show files with "foo" in name)
  foo_files = files_data.select { |file| file["file"].include?("foo") }
  foo_table = model.format_table(foo_files)
  # => formatted table showing only files with 'foo' in filename
  ```
check_coverage_data

Result:
```
┌────────────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                           │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ /home/kbennett/code/cov-loupe/lib/foo.rb   │   66.66% │         2 │       3 │   !   │
└────────────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 1, ok 0, stale 1
```

## 4. Filter by Coverage Threshold (only high-coverage files)
```ruby
# Filter by coverage percentage (e.g., only files >= 50% coverage)
high_coverage_files = files_data.select { |file| file["percentage"] && file["percentage"] >= 50.0 }
high_coverage_table = model.format_table(high_coverage_files)
# => formatted table showing only well-covered files
```

Result:
```
┌────────────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                           │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ /home/kbennett/code/cov-loupe/lib/foo.rb   │   66.66% │         2 │       3 │   !   │
└────────────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 1, ok 0, stale 1
```

## 5. Staleness Analysis
```ruby
# Analyze coverage staleness to find potentially problematic files
stale_files, healthy_files = files_data.partition { |file| file["stale"] }

puts "## Potentially Stale Coverage Files"
puts model.format_table(stale_files, sort_order: :descending)

puts "## Healthy Coverage Files"
puts model.format_table(healthy_files, sort_order: :descending)
```

Result:
```
## Potentially Stale Coverage Files
┌────────────────────────────────────────────────┬──────────┬───────────┬─────────┬───────┐
│ File                                           │        % │   Covered │   Total │ Stale │
├────────────────────────────────────────────────┼──────────┼───────────┼─────────┼───────┤
│ /home/kbennett/code/cov-loupe/lib/foo.rb   │   66.66% │         2 │       3 │   !   │
│ /home/kbennett/code/cov-loupe/lib/bar.rb   │   33.33% │         1 │       3 │   !   │
└────────────────────────────────────────────────┴──────────┴───────────┴─────────┴───────┘
Files: total 2, ok 0, stale 2

## Healthy Coverage Files
(No healthy files found)
```

NOTE: To see staleness analysis in action with both stale and healthy files,
try modifying file timestamps:
  - Make one file appear older: `touch -t 202401010000 spec/fixtures/project1/lib/foo.rb`
  - Or make one file appear newer: `touch spec/fixtures/project1/lib/bar.rb`
Then run this script again to see partition results change.

## Summary
This example demonstrates how cov-loupe can be used as a library to:
- Load and query coverage data
- Filter files by various criteria (directory, filename, coverage threshold)
- Perform staleness analysis to identify potentially problematic files
- Generate CI/CD integration reports with exit codes for monitoring
- Create custom reports tailored to specific needs

The table formatting functionality (format_table) is now accessible
directly in library mode, not just through the CLI!
