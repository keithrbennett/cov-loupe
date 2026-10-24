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

With SimpleCov 1.0 or later, this creates `coverage/coverage.json` (its default formatter writes it; 0.x does not, and a `coverage.json` from 0.x's separate `simplecov_json_formatter` gem lacks `meta.schema_version` and is rejected). cov-loupe reads the format written by SimpleCov 1.0 and later; SimpleCov is not installed with cov-loupe, so add it to your own project.

## 3. View Coverage

```sh
cov-loupe
```

You'll see a table showing coverage for each file, sorted by highest coverage first (lowest at the bottom).

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
- **[MCP Integration](user/MCP_INTEGRATION.md)** - Connect to AI assistants (Claude, ChatGPT)
- **[Troubleshooting](user/TROUBLESHOOTING.md)** - Common issues and solutions

## Integration with AI Assistants

If you're using Claude Code, ChatGPT, or another MCP-compatible assistant:

1. Configure your assistant to run `cov-loupe -m mcp` (see [MCP Integration Guide](user/MCP_INTEGRATION.md))
2. Use ready-made prompts from [Prompt Library](user/prompts/README.md)
3. Let AI analyze your coverage and suggest improvements

[Back to main README](../README.md)
