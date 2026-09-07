# Quick Start

[Back to main README](index.md)

Get up and running with cov-loupe in 3 steps.

## 1. Install

```sh
gem install cov-loupe
```

## 2. Generate Coverage

Run your test suite with SimpleCov enabled:

```sh
bundle exec rspec  # or your test command
```

This creates `coverage/coverage.json` (SimpleCov 1.0 or later is required).

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

- **[Installation Guide](user/INSTALLATION.md)** - Platform-specific setup, environment variables
- **[CLI Usage](user/CLI_USAGE.md)** - Complete command reference
- **[Examples](user/EXAMPLES.md)** - Common workflows and recipes
- **[MCP Integration](user/MCP_INTEGRATION.md)** - Connect to AI assistants (Claude, ChatGPT)
- **[Troubleshooting](user/TROUBLESHOOTING.md)** - Common issues and solutions

## Integration with AI Assistants

If you're using Claude Code, ChatGPT, or another MCP-compatible assistant:

1. Install the MCP server (see [MCP Integration Guide](user/MCP_INTEGRATION.md))
2. Use ready-made prompts from [Prompt Library](user/prompts/README.md)
3. Let AI analyze your coverage and suggest improvements

[Back to main README](index.md)
