# MCP Server Protocol Integration Tests

## Overview

This document describes the comprehensive integration tests added for the cov-loupe MCP server protocol in `spec/integration_spec.rb`.

## Test Coverage

The integration tests spawn the actual MCP server as a subprocess and communicate with it via JSON-RPC over stdio, testing the complete end-to-end protocol implementation.

### Tests Added (12 total)

1. **starts MCP server without errors** - Verifies the server starts and responds to basic requests without NameError or other initialization issues
2. **handles tools/list request** - Confirms all expected tools are properly registered
3. **executes file_coverage_summary via JSON-RPC** - Tests single-file coverage summary queries
4. **executes project_coverage via JSON-RPC** - Tests project-wide coverage (list/table/format)
5. **executes file_uncovered_lines via JSON-RPC** - Tests uncovered line detection
6. **executes help via JSON-RPC** - Tests help/documentation retrieval
7. **executes version via JSON-RPC** - Tests version information queries
8. **handles error responses for invalid tool calls** - Verifies graceful error handling
9. **handles malformed JSON-RPC requests** - Tests robustness against invalid input
10. **respects --log-file configuration in MCP mode** - Tests logging configuration
11. **prohibits stdout logging** - Ensures stdout isn't corrupted
12. **handles multiple sequential requests** - Tests statelessness and multi-request handling

## Why These Tests Are Critical

### Issue #1 from Analysis: Missing `require 'optparse'`

The critical bug (missing `require 'optparse'` in the `CovLoupe.run` entrypoint inside `lib/cov_loupe.rb`) was not caught by existing tests because:

- Unit tests loaded the full gem which transitively required optparse through the CLI
- MCP tools were tested in-process without spawning the server
- No integration tests verified the MCP server startup sequence

### What These Tests Catch

* ✅ **Server Initialization Errors**: NameError, LoadError, missing requires
* ✅ **Protocol Compliance**: Valid JSON-RPC request/response format
* ✅ **Tool Registration**: All tools properly configured and accessible
* ✅ **Data Accuracy**: Coverage data correctly passed from fixtures
* ✅ **Error Handling**: Graceful responses for invalid requests
* ✅ **Configuration**: Environment variables and options properly handled
* ✅ **Statelessness**: Multiple requests handled independently
* ✅ **Stream Integrity**: Stdout not corrupted by logging

## Test Architecture

### Helper Methods

- **`run_mcp_request(request_hash, timeout: 5)`**: Spawns MCP server, sends JSON-RPC request, returns stdout/stderr/status
- **`parse_jsonrpc_response(output)`**: Extracts JSON-RPC response from output (handles mixed stderr/stdout)

### Test Fixtures

Uses `spec/fixtures/project1/` with known coverage data:
- `lib/foo.rb`: 66.67% coverage (2/3 lines, line 2 uncovered)
- `lib/bar.rb`: 33.33% coverage (1/3 lines)

### Test Execution

```bash
# Run all MCP integration tests
bundle exec rspec spec/integration_spec.rb --tag slow

# Run specific integration test
bundle exec rspec spec/integration_spec.rb --example "executes file_coverage_summary via JSON-RPC"
```

## Performance

- Total execution time: ~2.1 seconds for all 12 tests
- Tagged with `:slow` to allow exclusion from quick test runs
- Uses `Open3.popen3` for subprocess management
- 5-second timeout per request (configurable)

## Coverage Impact

These tests increased the overall test count from 272 to 284 examples and improved confidence in the MCP server mode, which is the primary use case for AI assistant integration.

### Before Integration Tests
- 272 examples
- Missing `require 'optparse'` bug went undetected
- MCP server mode untested end-to-end

### After Integration Tests
- 284 examples
- MCP server startup verified
- Full JSON-RPC protocol tested
- Would catch Issue #1 immediately

## Future Enhancements

Potential additions:
- Test connection lifecycle (startup, multiple sessions, shutdown)
- Test concurrent requests (if supported)
- Test large coverage datasets (performance)
- Test network transport (if added)
- Test authentication/authorization (if added)

## Related Files

- `spec/integration_spec.rb` - Main integration test file (see the \"MCP server\" describe block)
- `lib/cov_loupe.rb` - Entry point with mode detection
- `lib/cov_loupe/mcp_server.rb` - MCP server implementation
- `exe/cov-loupe` - Executable entry point

## References

- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
