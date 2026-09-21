# Test Run Integration

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../index.md)

## Display Low Coverage Files

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
- `root:` - Project root directory (defaults to `SimpleCov.root` when SimpleCov is loaded, otherwise `'.'`)
- `coverage_file:` - Path to `coverage.json` or its directory (defaults to `SimpleCov.coverage_dir` when SimpleCov is loaded)
- `model:` - Pre-configured `CoverageModel` instance (optional, overrides `root:`/`coverage_file:`)

**Returns:** Formatted string, or `nil` if no files are below the threshold.

**SimpleCov Integration:** When SimpleCov is loaded, `CoverageReporter.report` automatically uses SimpleCov's configured root and coverage directory. You can override these by passing explicit `root:` or `coverage_file:` parameters, or provide a custom `model:` instance.

## Custom Coverage Directory

If your project uses a custom coverage directory:

```ruby
require 'simplecov'
SimpleCov.start do
  add_filter %r{^/spec/}
  coverage_dir 'reports/coverage'  # Custom coverage directory
  track_files 'lib/**/*.rb'
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  require 'cov_loupe'
  
  # CoverageReporter will automatically find the coverage in reports/coverage
  report = CovLoupe::CoverageReporter.report(threshold: 80, count: 5)
  puts report if report
end
```

Or specify the coverage file path explicitly:

```ruby
report = CovLoupe::CoverageReporter.report(
  threshold: 80,
  count: 5,
  coverage_file: 'reports/coverage/coverage.json'
)
```
