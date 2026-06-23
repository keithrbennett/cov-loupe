# Application Architecture

[Back to main README](../../index.md)

This document describes the core architectural decisions that shape how cov-loupe operates: its dual-mode design and context-aware error handling strategy.

## Table of Contents

- [Dual-Mode Operation (CLI and MCP Server)](#dual-mode-operation-cli-and-mcp-server)
- [Shared Resource Identifier Contract (CLI and MCP)](#shared-resource-identifier-contract-cli-and-mcp)
- [Context-Aware Error Handling](#context-aware-error-handling)

---

## Dual-Mode Operation (CLI and MCP Server)

### Status

Accepted

### Context

cov-loupe needed to serve two distinct use cases:

1. **Human users** wanting a command-line tool to inspect coverage reports in their terminal
2. **AI agents and MCP clients** needing programmatic access to coverage data via the Model Context Protocol (MCP) over JSON-RPC

We considered three approaches:

1. **Separate binaries/gems**: Create `simplecov-cli` and `cov-loupe` as separate projects
2. **Single binary with explicit mode flags**: Require users to pass `--mode mcp` to run as MCP server
3. **Automatic mode detection**: Single binary that automatically detects the operating mode based on input (TTY status, stdin)

#### Key Constraints

- MCP servers communicate via JSON-RPC over stdin/stdout, so any human-readable output would corrupt the protocol
- CLI users expect immediate, readable output without ceremony
- The gem should be simple to install and use for both audiences
- Mode selection must be reliable and unambiguous

### Decision (v4.0.0+)

We implemented **explicit mode selection** via the `-m/--mode` flag. The default mode is `cli`, and MCP users must pass `-m mcp` or `--mode mcp` to run the server.

#### Mode Selection Logic

The mode is determined by parsing the `-m/--mode` flag from argv (including environment variables via `COV_LOUPE_OPTS`):

- **Default**: CLI mode (when `-m/--mode` is not specified)
- **MCP mode**: Must explicitly pass `-m mcp` or `--mode mcp`

The implementation parses the configuration from the command-line arguments and routes to either `CoverageCLI` or `MCPServer` based on the mode setting.

#### Why This Works

- **MCP clients** are configured once with `-m mcp` or `--mode mcp` in their server config → always routes to MCP server
- **CLI users** don't need to specify anything → defaults to CLI mode
- **No ambiguity**: Mode is explicit and deterministic based on the `-m/--mode` flag

#### Historical Note

Prior to v4.0.0, cov-loupe used automatic mode detection based on TTY status and presence of subcommands. This was removed because:
- Automatic detection caused issues with piped input (`cov-loupe --format json > output.json` would hang in MCP mode)
- CI environments and non-TTY contexts were unpredictable
- CLI-only flags without subcommands (`--format`, `--sort-order`) couldn't be reliably detected
- Explicit mode selection is more predictable and follows standard practice for language servers

### Consequences

#### Positive

1. **User convenience**: Single gem to install (`gem install cov-loupe`), single executable (`cov-loupe`)
2. **Predictable behavior**: Mode is explicit and deterministic - no surprises based on environment
3. **Simpler implementation**: No complex mode detection logic to maintain
4. **Clear separation**: CLI and MCP server implementations remain completely separate after routing
5. **Follows conventions**: Matches standard practice for language servers (e.g., `typescript-language-server --stdio`)

#### Negative

1. **Breaking change**: Users upgrading from v3.x must update MCP server configuration to include `-m mcp` or `--mode mcp`
2. **Slight verbosity**: MCP users must include `-m mcp` or `--mode mcp` in their server config (but this is one-time setup)
3. **Shared dependencies**: Some components (error handling, coverage model) must work correctly in both modes

#### Trade-offs

- **Versus automatic detection**: More explicit, but eliminates ambiguity and edge cases
- **Versus separate gems**: Single installation is simpler, but requires mode flag for MCP

#### Future Constraints

- Shared components (like `CoverageModel`) must never output to stdout/stderr in ways that differ by mode
- Default mode must remain `cli` for backward compatibility with existing CLI users

### References

- Implementation: `lib/cov_loupe.rb` (`CovLoupe.run`)
- Configuration: `lib/cov_loupe/config/app_config.rb`
- CLI implementation: `lib/cov_loupe/cli.rb`
- MCP server implementation: `lib/cov_loupe/mcp_server.rb`
- Related section: [Context-Aware Error Handling](#context-aware-error-handling)

---

## Shared Resource Identifier Contract (CLI and MCP)

### Status

Accepted

### Context

cov-loupe exposes key project resources across two surfaces:

1. CLI (`cov-loupe --path-for=NAME`)
2. MCP (`help` response)

The project needs one consistent contract so humans and agents can request the same named values without translation logic.

### Decision (v4.1.0+)

Use one shared canonical map in `CovLoupe::Resources::RESOURCE_MAP` for both CLI and MCP.

Canonical identifiers:
- `repo` - public GitHub repository URL
- `docs` - public documentation site URL
- `docs-local` - absolute path to local `README.md`

Both interfaces now consume this same map:
- CLI uses `--path-for=NAME` (or `-p` alone to print all three) and prints the mapped value.
- `help` returns `resources` with the same canonical keys.
- MCP server startup instructions serialize the same resource map for discoverability.

### Consequences

#### Positive

1. One source of truth for resource values and names
2. Consistent contract for humans (CLI) and agents (MCP)
3. Lower maintenance cost and reduced documentation drift

#### Negative

1. Renaming or removing resource keys is a cross-surface API change
2. `docs-local` is a path, not a URL, so wording must stay precise in docs/help text

### References

- Shared resource map: `lib/cov_loupe/resources.rb`
- CLI option: `lib/cov_loupe/config/option_parser_builder.rb`
- MCP help response: `lib/cov_loupe/tools/help_tool.rb`
- MCP server instructions: `lib/cov_loupe/mcp_server.rb`

---

## Context-Aware Error Handling

### Status

Accepted

### Context

cov-loupe operates in three distinct contexts, each with different error handling requirements:

1. **CLI mode**: Human users expect friendly error messages, exit codes, and optional debug traces
2. **MCP server mode**: AI agents/clients need structured error responses that don't crash the server
3. **Library mode**: Embedding applications need exceptions they can catch and handle programmatically

Initially, we considered uniform error handling across all modes, but this created poor user experiences:

- CLI users saw raw exceptions with stack traces (scary and unhelpful)
- MCP servers crashed on errors instead of returning error responses
- Library users got friendly messages logged to stderr (unwanted side effects in their applications)

#### Key Requirements

- **CLI**: User-friendly messages, meaningful exit codes, optional stack traces for debugging
- **MCP Server**: Logged errors (to file, not stdout), structured JSON-RPC error responses, no server crashes
- **Library**: Raise custom exceptions with no logging, allowing consumers to handle errors as needed
- **Consistency**: Same underlying error types, but different presentation strategies

### Decision

We implemented a **context-aware error handling strategy** using three components:

#### 1. Custom Exception Hierarchy

All errors inherit from `CovLoupe::Error` (`lib/cov_loupe/errors/errors.rb`) with a `user_friendly_message` method:

```ruby
class Error < StandardError
  def user_friendly_message
    message  # Can be overridden in subclasses
  end
end

class FileNotFoundError < FileError; end
class CoverageDataError < Error; end
class ResultsetNotFoundError < CoverageDataError; end
# ... etc
```

This provides a unified interface for presenting errors to users while preserving exception types for programmatic handling.

#### 2. ErrorHandler Class

The `ErrorHandler` class (see `lib/cov_loupe/error_handler.rb`) provides configurable error handling behavior:

```ruby
class ErrorHandler
  attr_accessor :error_mode, :logger

  VALID_ERROR_MODES = [:off, :log, :debug].freeze

  def initialize(error_mode: :log, logger: nil)
    @error_mode = error_mode
    @logger = logger
  end

  def handle_error(error, context: nil, reraise: true)
    log_error(error, context)
    if reraise
      raise error.is_a?(CovLoupe::Error) ? error : convert_standard_error(error)
    end
  end
end
```

The `convert_standard_error` method transforms Ruby's standard errors into user-friendly custom exceptions:

- `Errno::ENOENT` → `FileNotFoundError`
- `JSON::ParserError` → `CoverageDataError`
- `Errno::EACCES` → `FilePermissionError`

#### 3. ErrorHandlerFactory

The `ErrorHandlerFactory` (defined in `lib/cov_loupe/error_handler_factory.rb`) creates mode-specific handlers:

```ruby
module ErrorHandlerFactory
  def self.for_cli(error_mode: :log)
    ErrorHandler.new(error_mode: error_mode)
  end

  def self.for_library(error_mode: :off)
    ErrorHandler.new(error_mode: :off)  # No logging
  end

  def self.for_mcp_server(error_mode: :log)
    ErrorHandler.new(error_mode: :log)   # Logs to file
  end
end
```

#### Error Flow by Mode

**CLI Mode** (lib/cov_loupe/cli.rb):
1. Catches all exceptions in the main run loop
2. Uses `for_cli` handler to log errors if debug mode is enabled
3. Displays `user_friendly_message` to the user
4. Exits with appropriate code (1 for errors, 2 for usage errors)

**MCP Server Mode** (`lib/cov_loupe/base_tool.rb`):
1. Each tool wraps execution in a rescue block
2. Uses `for_mcp_server` handler to log errors to `~/cov_loupe.log`
3. Returns structured JSON-RPC error response
4. Server continues running (no crashes)

**Library Mode** (`lib/cov_loupe.rb`):
1. Uses `for_library` handler with `error_mode: :off` (no logging)
2. Raises custom exceptions directly
3. Consumers catch and handle `CovLoupe::Error` subclasses

### Consequences

#### Positive

1. **Excellent UX**: Each context gets appropriate error handling behavior
2. **Robustness**: MCP server never crashes on tool errors
3. **Debuggability**: CLI users can enable stack traces with error modes, MCP errors are logged
4. **Clean library API**: No unwanted side effects (logging, stderr output) when used as a library
5. **Type safety**: Custom exceptions allow programmatic error handling by type

#### Negative

1. **Complexity**: Three error handling paths to maintain and test
2. **Coordination required**: All error types must implement `user_friendly_message` consistently
3. **Error conversion overhead**: Standard errors must be converted to custom exceptions

#### Trade-offs

- **Versus uniform error handling**: More code complexity, but dramatically better UX in each context
- **Versus separate error classes per mode**: Single error hierarchy is simpler, factory pattern adds mode-specific behavior

#### Implementation Notes

The `ErrorHandler.convert_standard_error` method uses pattern matching on exception types and error messages to provide helpful, context-aware error messages. This includes:

- Extracting filenames from system error messages
- Detecting SimpleCov-specific error patterns
- Providing actionable suggestions ("please run your tests first")

### References

- Custom exceptions: `lib/cov_loupe/errors/errors.rb`
- ErrorHandler implementation: `lib/cov_loupe/error_handler.rb`
- ErrorHandlerFactory: `lib/cov_loupe/error_handler_factory.rb`
- CLI error handling: `lib/cov_loupe/cli.rb` (rescue block in `CoverageCLI#run`)
- MCP tool error handling: `lib/cov_loupe/base_tool.rb` (`BaseTool#call`)
- Library mode: `lib/cov_loupe.rb` (error handling within `CovLoupe.run`)
- Related section: [Dual-Mode Operation](#dual-mode-operation-cli-and-mcp-server)
