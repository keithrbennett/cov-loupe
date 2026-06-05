# Troubleshooting Guide

[Back to main README](../index.md)

## Table of Contents

- [Running Issues](#running-issues)
- [Coverage Data Issues](#coverage-data-issues)
- [MCP Server Issues](#mcp-server-issues)
- [Diagnostic Commands](#diagnostic-commands)

## Running Issues

### Running the Test Suite with RVM (Codex macOS)

Codex's macOS sandbox forbids `/bin/ps`; RVM shells need it. When you run `bundle exec rspec` there, the shell falls back to macOS Ruby 2.6 and Bundler dies with `Gem::Resolver::APISet::GemParser` errors.

**Workarounds:**

- Run outside the macOS sandbox (Codex on Ubuntu, Gemini, Claude Code, local shells) or use a version manager that does not invoke `ps`.
- Or execute RSpec with explicit RVM paths:
  ```bash
  PATH="$HOME/.rvm/gems/ruby-3.4.5@cov-loupe/bin:$HOME/.rvm/rubies/ruby-3.4.5/bin:$PATH" \
    GEM_HOME="$HOME/.rvm/gems/ruby-3.4.5@cov-loupe" \
    GEM_PATH="$HOME/.rvm/gems/ruby-3.4.5@cov-loupe:$HOME/.rvm/gems/ruby-3.4.5@global" \
    $HOME/.rvm/rubies/ruby-3.4.5/bin/bundle exec rspec
  ```
- Use a different AI coding agent and/or operating system.

## Coverage Data Issues

### Missing `coverage/.resultset.json`

`cov-loupe` only reads coverage data; it never generates it. If you see "Could not find .resultset.json":

1. Run the test suite with SimpleCov enabled (default project setup already enables it).
   ```bash
   bundle exec rspec
   ls coverage/.resultset.json
   ```
2. If your coverage lives elsewhere, point the tools at it:
   ```bash
   cov-loupe -r build/coverage/.resultset.json  # -r = --resultset
   # or
   export COV_LOUPE_OPTS="-r build/coverage"
   ```

### Stale Coverage Errors

`--raise-on-stale` (or `-S`, or `raise_on_stale: true`) compares file mtimes and line counts
to the coverage snapshot and raises if stale. When it fails:

- Regenerate coverage (`bundle exec rspec`) so the snapshot matches current sources.
- Or drop back to warning-only behaviour using `--no-raise-on-stale` / `raise_on_stale: false`.

If you only care about a subset of files, supply `-g` / `--tracked-globs` (CLI) or `tracked_globs:`
(API) so new files outside those globs do not trigger staleness.

**Note:** If you see warnings about missing timestamps, time-based staleness checks may be skipped.
See [Timestamp Warnings](ADVANCED_USAGE.md#timestamp-warnings) for details.

### "No coverage data found for file"

The model looks up files by absolute path, then by relative path (stripping the project root). If you still hit this error:

1. Verify the file is listed in the coverage table (`cov-loupe list | grep model.rb` or `cov-loupe l | grep model.rb`).
2. Use the exact project-relative path that SimpleCov recorded (no symlinks; case-sensitivity
depends on your volume - see note below).
3. If the file truly never executes under tests, add coverage or exclude it from your workflow.

**Note on case-sensitivity:** `cov-loupe` auto-detects volume case-sensitivity at startup. 
On case-insensitive volumes (most macOS/Windows), `lib/Foo.rb` and `lib/foo.rb` are treated
as the same file. On case-sensitive volumes (most Linux, some macOS), they are different files.

### SimpleCov path consistency (merged resultsets)

When SimpleCov merges resultsets from multiple suites or environments, it can record the same file
under different path forms (for example, absolute vs relative, or with different roots). This is a
SimpleCov output issue, not a cov-loupe issue. Downstream tools will normalize paths and may treat
one entry as overriding another if two keys map to the same file.

**Recommendation:** Keep `SimpleCov.root` consistent across suites and avoid manual path rewriting
when merging resultsets.

## MCP Server Issues

### MCP Integration Not Working

**Symptoms:**
- AI assistant reports "Could not connect to MCP server"
- AI says "I don't have access to cov-loupe tools"

**Diagnostic steps:**

1. **Verify executable exists and works:**
   ```bash
   which cov-loupe
   cov-loupe --version
   ```

2. **Test MCP server mode manually:**
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp
   ```
   Should return JSON-RPC response.

3. **Verify MCP server is configured:**
   ```bash
   claude mcp list  # For Claude Code
   codex mcp list   # For Codex
   gemini mcp list  # For Gemini
   tail -f cov_loupe.log  # Check logs
   ```

4. **Restart AI assistant** - Config changes often require restart

5. **Use absolute path in MCP config:**
   ```bash
   # Find absolute path
   which cov-loupe

   # Update your MCP client config to use this path
   ```

6. **Use CLI as fallback:**

   If MCP still isn't working, you can use the CLI with `-fJ` flag instead.
   See **[CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md)** for complete guidance.

7. **Check for Codex environment variable issues:**
   If you are using Codex and the server fails to start due to missing gems, you need to manually add 
   `env_vars = ["GEM_HOME", "GEM_PATH"]` to your `~/.codex/config.toml`. 
   See the [MCP Integration - Codex section](MCP_INTEGRATION.md#codex) for complete setup instructions.

### RubyGems Wrapper Prints to Stdout Before MCP Startup

**Symptoms:**
- `cov-loupe -m mcp` prints `Resolving dependencies...` or similar text before any MCP response
- MCP clients fail with handshake/startup errors such as `connection closed` or `initialize response`
- The same `cov-loupe` install works in one project directory but not another

**Root cause:**

The generated RubyGems-installed `cov-loupe` launcher is not the same file as this repository's [`exe/cov-loupe`](../../exe/cov-loupe). A typical RubyGems stub looks like this:

```ruby
require 'rubygems'
Gem.use_gemdeps
Gem.activate_and_load_bin_path('cov-loupe', 'cov-loupe', version)
```

That `Gem.use_gemdeps` call can make the launcher inspect the current working directory for a `Gemfile` (via RubyGems/Bundler integration) before `cov-loupe` itself starts. On setups that also use `ruby_executable_hooks` and the `rubygems-bundler` plugin, the wrapper stack can do even more work up front by walking the current directory tree, loading Bundler, and trying to match the executable against the local bundle. If the current directory has a `Gemfile` but the bundle is unresolved, incomplete, or missing a lockfile, Bundler may resolve dependencies and emit progress text such as `Resolving dependencies...`.

For normal CLI use, that extra output is usually harmless. For MCP over stdio, it is fatal because the server must keep `stdout` clean until the protocol handshake begins.

Upstream tracking issue: [rvm/rvm#5649](https://github.com/rvm/rvm/issues/5649).

**Why one repo can fail while another works:**

- Repo A has a valid `Gemfile.lock` and `bundle check` succeeds, so Bundler has nothing noisy to do at startup.
- Repo B has a `Gemfile` but no settled bundle state, so the launcher triggers dependency resolution before `cov-loupe` starts.

Same launcher, same command, different working directory state.

**Why `bundle install` often fixes it:**

Running `bundle install` settles the bundle for that directory by creating/updating `Gemfile.lock` and installing required gems. After that, the launcher often stops printing dependency-resolution output, so MCP startup appears to recover.

This is the first fix to try. After `bundle install`, retry normal `cov-loupe -m mcp` startup before changing your MCP command.

This does not change MCP itself. It only changes whether the RubyGems wrapper stays quiet.

**How to confirm:**

1. Inspect the launcher path:
   ```bash
   which cov-loupe
   ```
2. Print the installed stub:
   ```bash
   sed -n '1,80p' "$(which cov-loupe)"
   ```
   If you see `Gem.use_gemdeps`, the launcher is bundle-sensitive.
3. Compare directories:
   ```bash
   bundle check
   ls Gemfile Gemfile.lock
   ```
4. Test MCP manually:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp 2>&1
   ```
   Any output before the JSON-RPC payload is a problem for MCP startup.

**Recommended workarounds:**

- Most reliable workaround in wrapper-heavy environments: launch `cov-loupe` through a small shell wrapper that disables `rubygems-bundler` noexec before the stub starts:
  ```bash
  #!/usr/bin/env bash
  export NOEXEC_DISABLE=1
  exec cov-loupe -m mcp "$@"
  ```
  Then point your MCP client at that wrapper script.
- Preferred fix: settle the current project's bundle, then retry normal startup:
  ```bash
  bundle install
  bundle check
  cov-loupe -m mcp
  ```
- Fallback: bypass the RubyGems wrapper and invoke the real executable directly:
  ```bash
  ruby -e 'spec = Gem::Specification.find_by_name("cov-loupe"); puts File.join(spec.full_gem_path, "exe", "cov-loupe")'
  ```
  Then use that path in your MCP config with `-m mcp`.
- For local development from a checkout, another fallback is to point the MCP client directly at the checkout's [`exe/cov-loupe`](../../exe/cov-loupe) instead of the RubyGems stub.

**Recommendation:**

Use either a wrapper that exports `NOEXEC_DISABLE=1` or normal `cov-loupe -m mcp` startup after the current project's bundle is settled. Only switch MCP clients to the real executable path if you need a fallback that is insulated from the working directory's Bundler state. For upstream discussion and any eventual fix, follow [rvm/rvm#5649](https://github.com/rvm/rvm/issues/5649).

### Path Issues with Version Managers

**Symptom:** `cov-loupe` works in terminal but not in MCP client.

**Cause:** MCP client doesn't have your shell environment (PATH, RVM, etc.).

**Solution:** Use absolute paths in MCP configuration:

```bash
# For rbenv/asdf - get the full absolute path
which cov-loupe
# Example output: /home/username/.rbenv/shims/cov-loupe
# Use this exact path in your MCP config

# For RVM you may need to create a wrapper and specify its absolute path
# (Replace ruby-3.3.8 with your rvm Ruby label) 
rvm wrapper ruby-3.3.8 cov-loupe cov-loupe

# Get the full path (expands ~ to your home directory)
realpath ~/.rvm/wrappers/ruby-3.3.8/cov-loupe
# Example output: /home/username/.rvm/wrappers/ruby-3.3.8/cov-loupe

# Use the FULL path in MCP config (NOT the ~ version):
# Good: /home/username/.rvm/wrappers/ruby-3.3.8/cov-loupe
# Bad:  ~/.rvm/wrappers/ruby-3.3.8/cov-loupe  (~ may not expand)
```

## Diagnostic Commands

Before reporting an issue, run these diagnostic commands and include the output:

```bash
# System info
ruby -v
gem -v
bundle -v

# cov-loupe info
gem list cov-loupe
which cov-loupe
cov-loupe --version

# Test basic functionality
cov-loupe --help
cov-loupe list 2>&1

# Check coverage data
ls -la coverage/.resultset.json
head -20 coverage/.resultset.json

# Test MCP mode
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp 2>&1
```

## Getting More Help

If the above doesn't solve your problem:

1. **Check error mode** - Run with `--error-mode debug` for full stack traces:
   ```bash
   cov-loupe --error-mode debug summary lib/cov_loupe/cli.rb
   ```

2. **Check logs:**
   ```bash
   # MCP server logs
   tail -50 cov_loupe.log

   # Or specify custom log location (--log-file or -l)
   cov-loupe -l /tmp/debug.log summary lib/cov_loupe/cli.rb
   ```

3. **Search existing issues:**
   https://github.com/keithrbennett/cov-loupe/issues

4. **Report a bug:**
   Include output from [Diagnostic Commands](#diagnostic-commands) above

## Related Documentation

- [Installation Guide](INSTALLATION.md) - Setup and PATH configuration
- [CLI Usage](CLI_USAGE.md) - Command-line options and examples
- [CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md) - Using CLI when MCP isn't available
- [MCP Integration](MCP_INTEGRATION.md) - MCP server configuration
- [Error Handling](ERROR_HANDLING.md) - Understanding error modes
