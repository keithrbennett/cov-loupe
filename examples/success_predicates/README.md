# Coverage Validation Predicate Examples

[Back to main README](../../docs/index.md)

This directory contains example coverage validation predicates for use with the `validate` subcommand.

> **⚠️ SECURITY WARNING**
>
> Validation predicates execute as **arbitrary Ruby code with full system privileges**. They have unrestricted access to:
> - File system operations (read, write, delete)
> - Network operations (HTTP requests, sockets)
> - System commands (via backticks, `system()`, `exec()`, etc.)
> - Environment variables and sensitive data
>
> **Only use predicate files from trusted sources.** Treat them like any other executable code in your project.
> - Never use predicates from untrusted or unknown sources
> - Review predicates before use, especially in CI/CD environments
> - Store predicates in version control with code review
> - Be cautious when copying examples from the internet

## Usage

**File mode:**
```sh
cov-loupe validate examples/success_predicates/<filename>.rb
```

**String mode:**
```sh
cov-loupe validate -i '->(model) { model.list["files"].all? { |f| f["percentage"] >= 80 } }'
```

The predicate receives a `CoverageModel` instance and returns:
- **Truthy value** → Exit code 0 (success)
- **Falsy value** → Exit code 1 (failure)
- **Exception** → Exit code 2 (error)

## Available Examples

### `all_files_above_threshold_predicate.rb`
All files must have >= 80% coverage.

```sh
cov-loupe validate examples/success_predicates/all_files_above_threshold_predicate.rb
```

### `project_coverage_minimum_predicate.rb`
Total project coverage must be >= 85%.

```sh
cov-loupe validate examples/success_predicates/project_coverage_minimum_predicate.rb
```

### `directory_specific_thresholds_predicate.rb`
Different thresholds for different directories:
- `lib/api/` - 85% required
- `lib/payments/` - 60% required
- `lib/ops/jobs/` - 80% required

```sh
cov-loupe validate examples/success_predicates/directory_specific_thresholds_predicate.rb
```

## Creating Custom Predicates

A predicate must be a callable object (lambda, proc, or class with `#call` method):

**Lambda example:**
```ruby
->(model) do
  model.list['files'].all? { |f| f['percentage'] >= 80 }
end
```

**Class method example:**
```ruby
class MyPolicy
  THRESHOLD = 80

  def self.call(model)
    model.list['files'].all? { |f| f['percentage'] >= THRESHOLD }
  end
end

MyPolicy  # The class itself
```

**Instance method example:**
```ruby
class MyPolicy
  def initialize(threshold = 80)
    @threshold = threshold
  end

  def call(model)
    model.list['files'].all? { |f| f['percentage'] >= @threshold }
  end
end

MyPolicy.new

```

### CoverageModel API

The `model` parameter provides:

```ruby
# Get all files
files = model.list['files']
# => [{ "file" => "...", "covered" => 12, "total" => 14, "percentage" => 85.71, "stale" => "ok" }, ...]

# Filter by globs
api_files = model.list(tracked_globs: ['lib/api/**/*.rb'])['files']

# Get specific file data
summary = model.summary_for('lib/model.rb')
uncovered = model.uncovered_for('lib/model.rb')
```

See [docs/user/LIBRARY_API.md](../../docs/user/LIBRARY_API.md) for the complete API.

### When to Use Standalone Scripts Instead

For more complex scenarios, you may prefer writing a standalone Ruby script that uses the `cov-loupe` library directly instead of using the `validate` subcommand.

**Use a standalone script when:**
- **External dependencies needed** - Your policy requires other gems or libraries
- **Complex setup required** - You need custom logging, database connections, or API calls
- **Easier testing desired** - Standalone scripts can be tested like any Ruby code
- **More explicit control** - You want full control over model initialization and error handling
- **Sophisticated logic** - Multi-step analysis, data aggregation, or integration with other tools

**Predicate approach is better when:**
- Policy is simple and self-contained (most common use case)
- You want the tool to handle option parsing (--coverage-file, --raise-on-stale, etc.)
- Consistent error handling and exit codes are desired
- Less boilerplate is preferred

**Example standalone script:**
```ruby
#!/usr/bin/env ruby
require 'cov_loupe'
require 'httparty'  # External gem

# Custom initialization
model = CovLoupe::CoverageModel.new(
  coverage_file: ENV['COVERAGE_PATH'],
  raise_on_stale: true
)

# Complex logic with external API
files = model.list['files']
low_coverage_files = files.select { |f| f['percentage'] < 80 }

# Post to Slack
if low_coverage_files.any?
  HTTParty.post(
    ENV['SLACK_WEBHOOK_URL'],
    body: { text: "#{low_coverage_files.size} files below 80%" }.to_json
  )
  exit 1
else
  exit 0
end
```

Both approaches execute arbitrary code with full system privileges, so the security considerations are identical. Choose the approach that best fits your use case.

## CI/CD Integration

**GitHub Actions:**
```yaml
- name: Enforce Coverage Policy
  run: bundle exec cov-loupe validate coverage_policy.rb
```

**GitLab CI:**
```yaml
coverage:enforce:
  script:
    - bundle exec cov-loupe validate coverage_policy.rb
```

**Jenkins:**
```groovy
stage('Coverage Policy') {
    steps {
        sh 'bundle exec cov-loupe validate coverage_policy.rb'
    }
}
```

## Exit Codes

- **0** - Predicate returned truthy (success)
- **1** - Predicate returned falsy (failure)
- **2** - Predicate raised an error

Use exit code 1 to fail CI/CD builds when coverage doesn't meet policy.
