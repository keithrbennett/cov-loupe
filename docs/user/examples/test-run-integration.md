# Test Run Integration

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../../README.md)

## Display Low Coverage Files

Add this to your `spec/spec_helper.rb` to report the files below a coverage threshold after each test run. Under Bundler, `require 'cov_loupe'` works only if cov-loupe is in your Gemfile (for example, in its `:test` group).

```ruby
require 'simplecov'
SimpleCov.start do
  skip %r{^spec/}
  cover 'lib/**/*.rb'  # Ensures new/untested files show up with 0%
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
    0.00%  lib/myapp/config_parser.rb
   19.30%  lib/myapp/formatters/source_formatter.rb
   24.00%  lib/myapp/model.rb
   26.00%  lib/myapp/cli.rb
   45.20%  lib/myapp/commands/base.rb
```

**Parameters:**

- `threshold:` - Coverage percentage below which files are included (default: 80)
- `count:` - Maximum number of files to show (default: 5)
- `root:` - Project root directory (defaults to `SimpleCov.root` when SimpleCov is loaded, otherwise `'.'`)
- `coverage_file:` - Path to `coverage.json` or its directory (defaults to `SimpleCov.coverage_dir` under the effective root when SimpleCov is loaded, so passing `root:` alone moves it too)
- `model:` - Pre-configured `CoverageModel` instance (optional, overrides `root:`/`coverage_file:`)

**Returns:** Formatted string, or `nil` if no files are below the threshold.

When SimpleCov is loaded, as in an `at_exit` hook, `report` uses SimpleCov's configured root and coverage directory. Passing `root:` replaces the root and looks for SimpleCov's coverage directory under the new root; passing `coverage_file:` or `model:` replaces the coverage location entirely.

## Custom Coverage Directory

If your project uses a custom coverage directory:

```ruby
require 'simplecov'
SimpleCov.start do
  skip %r{^spec/}
  coverage_dir 'reports/coverage'  # Custom coverage directory
  cover 'lib/**/*.rb'
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
