# Installation Guide

[Back to main README](../index.md)

## Prerequisites

- **Ruby >= 3.2** (required by the `mcp` dependency)
- SimpleCov-generated `.resultset.json` file in your project

## Quick Install

### Via RubyGems

```sh
gem install cov-loupe
```

### Via Bundler

Add to your `Gemfile`:

```ruby
gem 'cov-loupe'
```

Then run:

```sh
bundle install
```

### Prerelease Versions

See [Installing a Prerelease](installing-a-prelease-version-of-covloupe.md) for instructions on installing prerelease versions.

### From Source

```sh
git clone https://github.com/keithrbennett/cov-loupe.git
cd cov-loupe
bundle install
gem build cov-loupe.gemspec
gem install cov-loupe-*.gem
```

## Require Path

The gem uses a single require path:

```ruby
require "cov_loupe"
```

The executable is `cov-loupe` (with hyphen).

## Verification

### Test Installation

```sh
# Check version
cov-loupe --version

# Show help
cov-loupe --help

# Run on current project (requires coverage data)
cov-loupe
```

### Generate Test Coverage

If you don't have coverage data yet:

```sh
# Run your tests with SimpleCov enabled
bundle exec rspec  # or your test command

# Verify coverage file exists
ls -l coverage/.resultset.json

# Now test cov-loupe
cov-loupe
```

## Platform-Specific Notes

### macOS

Works with system Ruby or any version manager. Recommended: use rbenv or asdf, not rvm (see note below).

**Note:** RVM may not work in sandboxed environments (e.g., AI coding assistants) because it requires `/bin/ps`, which sandbox restrictions often block. Use rbenv or chruby instead for sandboxed environments.

### Linux

Works with system Ruby or any version manager.

### Windows

Should work with Ruby installed via RubyInstaller. PATH configuration may differ.

## Upgrading

If you are upgrading from an earlier version of `cov-loupe`, please check the migration guides:

- [Migrating to v6](migrations/MIGRATING_TO_V6.md)
- [Migrating to v5](migrations/MIGRATING_TO_V5.md)
- [Migrating to v4](migrations/MIGRATING_TO_V4.md)
- [Migrating to v3](migrations/MIGRATING_TO_V3.md)
- [Migrating to v2](migrations/MIGRATING_TO_V2.md)

## Next Steps

- **[CLI Usage](CLI_USAGE.md)** - Learn command-line options
- **[Library API](LIBRARY_API.md)** - Use in Ruby code
- **[MCP Integration](MCP_INTEGRATION.md)** - Connect to AI assistants
- **[Troubleshooting](TROUBLESHOOTING.md)** - More detailed troubleshooting
