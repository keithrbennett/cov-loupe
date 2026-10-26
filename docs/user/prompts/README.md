# Prompt Library

[Back to main README](../../../README.md)

Starter prompts you can paste into MCP-compatible assistants when you need cov-loupe to run targeted reports. To fall back to the CLI when MCP is unavailable, see [CLI Fallback for LLMs](../CLI_FALLBACK_FOR_LLMS.md).

- [Test Coverage Analysis by Logical Area](test-coverage-analysis-prompt.md) – Unattended, line-level analysis that groups coverage by logical areas (down to individual classes and methods) and ranks gaps by risk; reads coverage from a passing, up-to-date test run (it does not run tests), so several agents can run it concurrently, headless or interactively
