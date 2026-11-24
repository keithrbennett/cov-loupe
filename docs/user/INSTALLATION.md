# Installation Guide

[Back to main README](../../README.md)

## Prerequisites

- **Ruby >= 3.3** (the oldest Ruby that has not reached end of life)
- In the project you inspect, a `coverage/coverage.json` written by SimpleCov 1.x. SimpleCov's default HTML formatter writes it, as does its JSON formatter. cov-loupe does not install SimpleCov.

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

A gem installed this way is run through Bundler, so prefix commands with `bundle exec` (for example, `bundle exec cov-loupe --version`), or generate a binstub with `bundle binstubs cov-loupe` and run `bin/cov-loupe`.

### Prerelease Versions

See [Installing a Prerelease](installing-a-prerelease-version-of-covloupe.md) for instructions on installing prerelease versions.

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

The executable is `cov-loupe` (with a hyphen). If your shell reports `command not found`, the cause is usually one of these:

- The gem's executable directory is not on your `PATH`. Check it with `gem environment`. If your Ruby version manager uses shims, see its documentation for refreshing them after a gem install.
- The gem was installed only through Bundler. Run it with `bundle exec cov-loupe`.

## Verification

### Test Installation

```sh
# Check version
cov-loupe --version

# Show help
cov-loupe --help

# Run on current project (requires coverage data)
cov-loupe list
```

### Generate Test Coverage

If your project doesn't use SimpleCov 1.x yet, follow [Quick Start step 2](../QUICKSTART.md#2-generate-coverage) to add it and run your tests. Then confirm the coverage file exists and try cov-loupe:

```sh
ls -l coverage/coverage.json
cov-loupe list
```

## Platform-Specific Notes

### macOS

The system Ruby that ships with macOS is older than the required 3.3. Use the Ruby your project's tests run under if it is 3.3 or later; otherwise install a current Ruby with Homebrew or a Ruby version manager (see [Installing Ruby](https://www.ruby-lang.org/en/documentation/installation/)).

### Linux

Works with any Ruby 3.3 or later. If your distribution's packaged Ruby is older, see [Installing Ruby](https://www.ruby-lang.org/en/documentation/installation/).

### Windows

cov-loupe should work with Ruby installed via RubyInstaller. If `cov-loupe` is not found, check that the gem executable directory reported by `gem environment` is on your `PATH`.

## RVM

If you use RVM, see Troubleshooting for [sandboxed environments](TROUBLESHOOTING.md#running-the-test-suite-with-rvm-codex-macos), [MCP clients that cannot find cov-loupe](TROUBLESHOOTING.md#path-issues-with-version-managers), and [`Resolving dependencies...` before MCP startup](TROUBLESHOOTING.md#rubygems-wrapper-prints-to-stdout-before-mcp-startup).

## Upgrading

If you are upgrading from an earlier version of `cov-loupe`, please check the migration guides:

- [Migrating to v7](migrations/MIGRATING_TO_V7.md)
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
