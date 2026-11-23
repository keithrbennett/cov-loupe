# Prompt Library

[Back to main README](../../../README.md)

Prompts you can give an AI assistant to produce complete coverage reports with cov-loupe. To use the CLI when MCP is unavailable, see [CLI Fallback for LLMs](../CLI_FALLBACK_FOR_LLMS.md). For shorter, single-question prompts, see [AI Assistant Prompts](../examples/ai-assistant-prompts.md).

- [Test Coverage Analysis by Logical Area](test-coverage-analysis-prompt.md) – An unattended, line-level analysis that groups coverage by logical area (down to individual classes and methods) and ranks gaps by risk. It reads coverage from a passing, up-to-date test run and does not run tests itself, so several agents can run it at once, headless or interactively.
