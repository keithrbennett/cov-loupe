# Quick Start

[Back to main README](../README.md)

Get up and running with cov-loupe in 3 steps.

## 1. Install

cov-loupe requires Ruby 3.3 or later.

```sh
gem install cov-loupe
```

## 2. Generate Coverage

If your project doesn't use SimpleCov yet, add it to your `Gemfile` and install it:

```sh
bundle add simplecov --group test --require false
```

Then start it at the very top of `spec/spec_helper.rb` (or `test/test_helper.rb`), before your application code loads:

```ruby
require 'simplecov'
SimpleCov.start
```

Then run your test suite:

```sh
bundle exec rspec  # or your test command
```

With SimpleCov 1.0 or later, this creates `coverage/coverage.json`, the file cov-loupe reads. SimpleCov 0.x does not write it by default, and cov-loupe rejects the `coverage.json` written by `simplecov_json_formatter` (the separate gem used with 0.x) because it lacks `meta.schema_version`. cov-loupe does not install SimpleCov, so add it to your project as shown above.

## 3. View Coverage

Run it from your project root (or pass `-R path/to/project`):

```sh
cov-loupe
```

You'll see a table of coverage for each file, sorted from highest to lowest coverage. Files with no coverable lines show `n/a` and are listed above the 100% files.

## Common Commands

```sh
# Check a specific file ('summary' or 's')
cov-loupe summary lib/my_file.rb
cov-loupe s lib/my_file.rb

# See uncovered lines ('uncovered' or 'u')
cov-loupe uncovered lib/my_file.rb
cov-loupe u lib/my_file.rb

# Get overall project stats ('totals' or 't')
cov-loupe totals
cov-loupe t

# View all commands
cov-loupe --help
```

## Next Steps

- **[Installation Guide](user/INSTALLATION.md)** - Platform-specific setup and troubleshooting
- **[CLI Usage](user/CLI_USAGE.md)** - Complete command reference
- **[Examples](user/EXAMPLES.md)** - Common workflows and recipes
- **[MCP Integration](user/MCP_INTEGRATION.md)** - Connect to AI assistants (Claude Code, Codex, Cursor, and others)
- **[Troubleshooting](user/TROUBLESHOOTING.md)** - Common issues and solutions

## Integration with AI Assistants

If you're using Claude Code, Codex, or another MCP-compatible assistant:

1. Configure your assistant to run `cov-loupe -m mcp` (see [MCP Integration Guide](user/MCP_INTEGRATION.md))
2. Use ready-made prompts from [Prompt Library](user/prompts/README.md)
3. Ask the assistant to analyze your coverage and suggest improvements

[Back to main README](../README.md)
