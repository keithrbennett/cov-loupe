# Troubleshooting Guide

[Back to main README](../../README.md)

## Table of Contents

- [Coverage Data Issues](#coverage-data-issues)
- [Logging Target Issues](#logging-target-issues)
- [MCP Server Issues](#mcp-server-issues)
- [Development Environment Issues](#development-environment-issues)
- [Diagnostic Commands](#diagnostic-commands)
- [Getting More Help](#getting-more-help)
- [Related Documentation](#related-documentation)

## Coverage Data Issues

### Missing coverage file

`cov-loupe` only reads coverage data; it never generates it. It reads `coverage.json`,
which SimpleCov 1.0.0 and later write alongside the HTML report. SimpleCov 0.x writes
only `.resultset.json` by default, which cov-loupe no longer reads; upgrade SimpleCov to
1.0 or later. If you see "Could not find coverage.json":

1. Run the test suite with SimpleCov enabled (see [Quick Start](../QUICKSTART.md) to set it up).
   ```bash
   bundle exec rspec
   ls coverage/coverage.json
   ```
2. If your coverage lives elsewhere, point the tools at it:
   ```bash
   cov-loupe -c build/coverage/coverage.json list  # -c = --coverage-file
   # or
   export COV_LOUPE_OPTS="-c build/coverage"
   ```

### Unsupported coverage.json format

cov-loupe checks `meta.schema_version` in `coverage.json` (the file format version, not the
SimpleCov gem version) and accepts any 1.x. If the value is missing or has another major
version, loading fails with (the CLI adds the `Coverage data error:` prefix):

```
Coverage data error: Unsupported coverage.json format (meta.schema_version: nil; meta.simplecov_version: "0.22.0") in <path>; cov-loupe requires format 1.x (written by SimpleCov 1.0 and later)
```

The `meta.simplecov_version` part appears only when the file records it.

- **Missing value (`nil`):** the file was usually written for SimpleCov 0.x by the separate
  `simplecov_json_formatter` gem, or rewritten by another tool that dropped the field.
  Upgrade SimpleCov to 1.0 or later and re-run the test suite, or make sure the rewriting
  tool preserves `meta.schema_version`.
- **Newer major version (e.g. `"2.0"`):** the file uses a format this cov-loupe release does
  not read. Upgrade cov-loupe if a newer release supports it, or pin SimpleCov to a version
  that writes format 1.x.

### Coverage file has no line coverage

cov-loupe reports line coverage only. If SimpleCov ran with line coverage turned off
(`disable_coverage :line`, keeping only branch or method coverage), `coverage.json` lists
files but none has a `lines` array, and loading fails with (the CLI adds the
`Corrupt coverage data:` prefix):

```
Corrupt coverage data: Coverage file has no line coverage (no entry has a lines array): <path>; cov-loupe reports line coverage only. If SimpleCov ran with `disable_coverage :line`, re-enable it with `enable_coverage :line`
```

Re-enable line coverage in your SimpleCov configuration (it can run alongside branch and
method coverage) and re-run the test suite. A `coverage.json` that lists no files at all still
loads, and reports no coverage data.

### Stale Coverage Errors

`--raise-on-stale true` (or `-S true`, or `raise_on_stale: true`) makes a query fail instead of
reporting problems with the coverage data:

- **Per-file queries** (`summary`, `uncovered`, `detailed`, `raw`) fail if the source file was
  modified after the coverage run or its line count differs from the coverage data. A deleted or
  unreadable source file fails as a file error instead.
- **Project queries** (`list`, `totals`, and `validate` predicates that call
  `model.list` or `model.project_totals`) fail if any file in the coverage data is newer, has a
  different line count, is deleted, or is unreadable. With file globs, they also fail for a
  matching file that is not in the coverage data.
- **Skipped rows:** project queries also fail if any coverage row has invalid data, whether or
  not it matches the file globs.

See [Stale Coverage Errors](ERROR_HANDLING.md#stale-coverage-errors) for the exception each case
raises. When it fails:

- Regenerate coverage (`bundle exec rspec`) so it matches the current sources.
- Or report staleness without failing, with `--raise-on-stale false` / `raise_on_stale: false`.

If you only care about a subset of files, pass `-g` / `--file-globs` (CLI) or `file_globs:`
(API). Project queries then check staleness only for files matching those globs; a skipped
coverage row still fails, as noted above.

**Note:** If you see warnings about missing timestamps, time-based staleness checks may be skipped.
See [Timestamp Warnings](ADVANCED_USAGE.md#timestamp-warnings) for details.

### "The project root may be wrong"

Coverage paths are project-relative, so cov-loupe looks for each source file under the project
root, which defaults to the current directory. It warns when more than half of the files with
coverage rows are not found there (rows skipped as malformed are not counted). With file globs,
the count covers only the files the globs match.

A typical cause is a `--coverage-file` that points into another project while the root is still
the current directory. The same warning also appears when the source files really were removed,
or when the coverage was generated on another machine.

Set the root with `--root PATH` (CLI) or the `root` argument (MCP, Ruby). If `coverage.json`
records an absolute root (`meta.root`, written by SimpleCov 1.x) that differs from the current
one and is a directory on this machine, the warning suggests it; cov-loupe never switches to it
on its own.

The warning does not change the exit status. With `--raise-on-stale true`, however, the
project-level commands (`list` and `totals`) exit non-zero and show the
same message after the staleness summary.

### "No coverage entry found for ..."

This is a `CoverageEntryNotFoundError` (a `CoverageDataError`). The model looks up files by absolute path, then by relative path (stripping the project root). If you still hit this error:

1. Verify the file is listed in the coverage table (`cov-loupe list | grep model.rb`).
2. Use the exact project-relative path that SimpleCov recorded (no symlinks; whether case
   matters depends on your volume, as described below).
3. If the file is never loaded during tests, add tests for it or stop querying it.

**Note on case sensitivity:** `cov-loupe` detects whether the volume is case-sensitive at startup.
On case-insensitive volumes (most macOS/Windows), `lib/Foo.rb` and `lib/foo.rb` are treated
as the same file. On case-sensitive volumes (most Linux, some macOS), they are different files.

### SimpleCov path consistency (merged results)

When SimpleCov merges results from multiple suites or environments, it can record the same file
under different path forms (for example, absolute vs relative, or with different roots). This is a
SimpleCov output issue, not a cov-loupe issue. cov-loupe normalizes paths, and if two keys map to
the same file it fails with a `CoverageDataError` naming the colliding keys, rather than silently
using one of them.

**Recommendation:** Keep `SimpleCov.root` consistent across suites and avoid manual path rewriting
when merging results.

## Logging Target Issues

cov-loupe probes file-based logging targets when the logger is initialized. If
the target cannot be accessed, the failure is reported early instead of waiting
for the first diagnostic. See the [logging initialization and target testing
guide](LOGGING.md#log-file-initialization-and-target-testing) for the complete
behavior.

Check the following when you see an `Unable to use log target` message:

- Verify that the configured directory exists and is writable by the process.
- Check the path supplied by `--log-file`/`-l`, `COV_LOUPE_OPTS`, or the MCP
  server configuration.
- Use `-l stderr` to send diagnostics to standard error while troubleshooting,
  or use `-l off` to disable logging.
- In MCP mode, a logging initialization failure causes affected tool calls to
  return `isError: true`; correct the target or disable logging and restart the
  server.

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

2. **Smoke-test MCP server mode manually:**
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp
   ```
   This should return a JSON-RPC response, confirming that the server launches and responds over
   stdio. It is not an exhaustive contract test; see
   [MCP Integration — Error Responses](MCP_INTEGRATION.md#error-responses) for optional validation
   and error sanity checks and the full failure model.

3. **Verify MCP server is configured:**
   ```bash
   claude mcp list  # For Claude Code
   codex mcp list   # For Codex
   agy mcp list     # For Antigravity
   gemini mcp list  # For Gemini CLI (Gemini Code Assist licenses only)
   # MCP hosts capture the server's stderr by default.
   # For a persistent file, configure --log-file PATH and inspect that path.
   ```

4. **Restart AI assistant** - Config changes often require restart

5. **Use absolute path in MCP config:**
   ```bash
   # Find absolute path
   which cov-loupe

   # Update your MCP client config to use this path
   ```
   See [Path Issues with Version Managers](#path-issues-with-version-managers) for which path to use, including under RVM.

6. **Use CLI as fallback:**

   If MCP still isn't working, have the agent use the CLI with `-fJ` instead.
   See **[CLI Fallback for LLMs](CLI_FALLBACK_FOR_LLMS.md)** for complete guidance.

7. **Check for Codex environment variable issues:**
   If you use Codex and the server fails to start because gems are missing, add
   `env_vars = ["GEM_HOME", "GEM_PATH"]` to your `~/.codex/config.toml` by hand.
   See the [MCP Integration - Codex section](MCP_INTEGRATION.md#codex) for complete setup instructions.

### RubyGems Wrapper Prints to Stdout Before MCP Startup

**Symptoms:**

- `cov-loupe -m mcp` prints `Resolving dependencies...` or similar text before any MCP response
- MCP clients fail with handshake/startup errors such as `connection closed` or `initialize response`
- The same `cov-loupe` install works in one project directory but not another

**Root cause:**

The generated RubyGems-installed `cov-loupe` launcher is not the same file as this repository's [`exe/cov-loupe`](https://github.com/keithrbennett/cov-loupe/blob/main/exe/cov-loupe). A typical RubyGems stub looks like this:

```ruby
require 'rubygems'
Gem.use_gemdeps
Gem.activate_and_load_bin_path('cov-loupe', 'cov-loupe', version)
```

That `Gem.use_gemdeps` call can make the launcher inspect the current working directory for a `Gemfile` (via RubyGems/Bundler integration) before `cov-loupe` itself starts. On setups that also use `ruby_executable_hooks` and the `rubygems-bundler` plugin, the wrapper stack can do even more work up front by walking the current directory tree, loading Bundler, and trying to match the executable against the local bundle. If the current directory has a `Gemfile` but the bundle is unresolved, incomplete, or missing a lockfile, Bundler may resolve dependencies and emit progress text such as `Resolving dependencies...`.

For normal CLI use, that extra output is usually harmless. For MCP over stdio, it is fatal because `stdout` must carry only protocol messages, from startup until the server exits.

Upstream tracking issue: [rvm/rvm#5649](https://github.com/rvm/rvm/issues/5649).

**Why one repo can fail while another works:**

- Repo A has a valid `Gemfile.lock` and `bundle check` succeeds, so Bundler has nothing noisy to do at startup.
- Repo B has a `Gemfile` but no settled bundle state, so the launcher triggers dependency resolution before `cov-loupe` starts.

Same launcher, same command, different working directory state.

**Why `bundle install` often fixes it:**

`bundle install` settles the bundle for that directory: it creates or updates `Gemfile.lock` and installs the required gems. The launcher then usually has nothing to print, so MCP startup succeeds. It changes nothing about cov-loupe itself, only whether the RubyGems wrapper stays quiet.

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
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp 2>/dev/null
   ```
   Any stdout output before the JSON-RPC payload is a problem for MCP startup. stderr is discarded here, because log lines there are harmless; if the command prints nothing at all, run it again without `2>/dev/null` to see why the launcher failed (for example, `can't find gem cov-loupe`).

**Workarounds, in order.** Step 1 fixes one project at a time; with RVM, or if you use cov-loupe in many projects, go straight to step 2.

1. **Settle the project's bundle**, then retry normal startup. This fixes the problem for that project:
   ```bash
   bundle install
   bundle check
   ```
   Then repeat the manual test in step 4 of **How to confirm**.
2. **Use a launch wrapper** that disables the `rubygems-bundler` noexec hook before the stub starts. This works in every project, and is the most reliable fix in RVM and similar environments:
   ```bash
   #!/usr/bin/env bash
   export NOEXEC_DISABLE=1
   exec cov-loupe -m mcp "$@"
   ```
   Point your MCP client at the wrapper script. If the client doesn't pass your shell's Ruby setup, the `exec` line needs an absolute path, such as RVM's wrapper (see [Path Issues with Version Managers](#path-issues-with-version-managers)). For step-by-step setup, including the command for each client, see [Step by Step: The Launch Wrapper](MCP_INTEGRATION.md#step-by-step-the-launch-wrapper).
3. **Bypass the RubyGems wrapper** and invoke the real executable, which does not depend on the working directory's bundle at all. Find its path with:
   ```bash
   ruby -e 'spec = Gem::Specification.find_by_name("cov-loupe"); puts File.join(spec.full_gem_path, "exe", "cov-loupe")'
   ```
   Then use that path, with `-m mcp`, in your MCP config. Under RVM, the client must also pass `GEM_HOME` and `GEM_PATH` (see [Path Issues with Version Managers](#path-issues-with-version-managers)); otherwise use step 2.

For local development from a checkout, point the MCP client directly at the checkout's [`exe/cov-loupe`](https://github.com/keithrbennett/cov-loupe/blob/main/exe/cov-loupe) instead of the RubyGems stub.

For upstream discussion and any eventual fix, follow [rvm/rvm#5649](https://github.com/rvm/rvm/issues/5649).

### Path Issues with Version Managers

**Symptom:** `cov-loupe` works in terminal but not in MCP client.

**Cause:** MCP client doesn't have your shell environment (PATH, RVM, etc.).

**Solution:** Put a full absolute path to cov-loupe in your MCP configuration, not a `~` path, which may not expand. The path must start a Ruby that has cov-loupe installed. Which Ruby that is depends on your version manager:

- **Shim-based managers** (such as rbenv): `which cov-loupe` prints a shim. A shim picks the Ruby from the client's working directory, so cov-loupe must be installed for the Ruby each project selects.
- **RVM:** use the wrapper RVM generates, which sets up that Ruby's environment. A bare path to the executable needs RVM's `GEM_HOME` and `GEM_PATH`, which an MCP client does not set.

Check the path again after you upgrade or remove a Ruby. If you use the [launch wrapper](MCP_INTEGRATION.md#step-by-step-the-launch-wrapper), put this path in its `exec` line and keep registering the wrapper, so its `NOEXEC_DISABLE=1` still applies.

```bash
# Shim-based managers
which cov-loupe
# Example output: /home/username/.rbenv/shims/cov-loupe

# RVM: the wrapper for the current Ruby
rvm wrapper show cov-loupe
# Example output: /home/username/.rvm/gems/ruby-3.3.8/wrappers/cov-loupe
```

## Development Environment Issues

### Running the Test Suite with RVM (Codex macOS)

Codex's macOS sandbox forbids `/bin/ps`, which RVM shells need. When you run `bundle exec rspec` there, the shell falls back to macOS Ruby 2.6, and Bundler fails with `Gem::Resolver::APISet::GemParser` errors.

**Workarounds:**

- Run outside the macOS sandbox (Codex on Ubuntu, Gemini, Claude Code, local shells) or use a version manager that does not invoke `ps`.
- Or execute RSpec with explicit RVM paths (replace `3.4.5` and the `cov-loupe` gemset with your own):
  ```bash
  PATH="$HOME/.rvm/gems/ruby-3.4.5@cov-loupe/bin:$HOME/.rvm/rubies/ruby-3.4.5/bin:$PATH" \
    GEM_HOME="$HOME/.rvm/gems/ruby-3.4.5@cov-loupe" \
    GEM_PATH="$HOME/.rvm/gems/ruby-3.4.5@cov-loupe:$HOME/.rvm/gems/ruby-3.4.5@global" \
    $HOME/.rvm/rubies/ruby-3.4.5/bin/bundle exec rspec
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
ls -la coverage/coverage.json
head -20 coverage/coverage.json

# Test MCP mode
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp 2>&1
```

## Getting More Help

If the above doesn't solve your problem:

1. **Get stack traces** - Run with `--error-mode debug`:
   ```bash
   cov-loupe --error-mode debug summary lib/my_app/order.rb
   ```

2. **Check the logs.** cov-loupe logs to stderr by default; for an MCP server, your MCP client captures it. To keep a log, pass `--log-file` (`-l`) and inspect that file:
   ```bash
   cov-loupe -l /tmp/debug.log summary lib/my_app/order.rb
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
