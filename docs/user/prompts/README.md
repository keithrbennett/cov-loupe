# Prompt Library

[Back to main README](../../../README.md)

Starter prompts you can paste into MCP-compatible assistants when you need cov-loupe to run targeted reports or fall back to CLI execution.

- [Coverage Analysis](coverage-analysis-prompt.md) – Analyze coverage for any Ruby project; adapts component categories to the framework in use (Rails example included)
- [Test Coverage Analysis by Logical Area](test-coverage-analysis-prompt.md) – Unattended, line-level analysis that groups coverage by logical areas (down to individual classes and methods) and ranks gaps by risk; runs the test suite first and works headless
- [Use CLI Instead of MCP](use-cli-not-mcp-prompt.md) – Include in another prompt to instruct the model to use cov-loupe CLI as a fallback when MCP transport is blocked or unavailable
