# Examples and Recipes

[Back to main README](../../README.md)

Practical examples for common tasks with cov-loupe, one page per topic.

## Ask Your AI Assistant

- **[AI Assistant Prompts](examples/ai-assistant-prompts.md)** – Prompts for the MCP server that go beyond tables and counts: explain which behaviors your tests don't exercise and what would happen if they broke, rank gaps by risk instead of percentage, judge whether your tests would actually catch failures, review a branch, and write tests that are checked against real coverage data. Start here if you use cov-loupe with an AI assistant.

## From the Command Line and Ruby

- **[CLI Usage Examples](CLI_USAGE.md#examples)** – Coverage checks, file investigation, and JSON processing with `jq`, Ruby, and rexe.
- **[Library API Guide](LIBRARY_API.md#advanced-recipes)** – Ruby recipes: batch analysis, threshold checks, directory-level aggregation, delta tracking, and custom reports.

## In Your Test Runs and CI

- **[Test Run Integration](examples/test-run-integration.md)** – Report the lowest-coverage files at the end of every test run.
- **[CI/CD Integration](examples/ci-cd-integration.md)** – Coverage thresholds in GitHub Actions and GitLab CI, stale-coverage checks, and custom success predicates.

## Example Scripts

- **[Success Predicates](../../examples/success_predicates/README.md)** - Custom coverage policy examples, from the repository's `examples/success_predicates/` directory

## Related Documentation

- [CLI Usage Guide](CLI_USAGE.md) - Complete command reference
- [Library API Guide](LIBRARY_API.md) - Ruby API documentation
- [MCP Integration](MCP_INTEGRATION.md) - AI assistant setup
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
