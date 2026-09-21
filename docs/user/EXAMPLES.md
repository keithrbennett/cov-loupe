# Examples and Recipes

[Back to main README](../index.md)

Practical examples for common tasks with cov-loupe, one page per topic.

## Ask Your AI Assistant

- **[AI Assistant Prompts](examples/ai-assistant-prompts.md)** – Prompts for the MCP server that go beyond tables and counts: explain which behaviors your tests don't exercise and what would happen if they broke, rank gaps by risk instead of percentage, judge whether your tests would actually catch failures, review a branch, and write tests that are checked against real coverage data. Start here if you use cov-loupe with an AI assistant.

## From the Command Line and Ruby

- **[Quick Start Examples](examples/quick-start-examples.md)** – View all coverage, check one file, and find gaps in a few commands.
- **[CLI Examples](examples/cli-examples.md)** – Detailed coverage analysis, and working with JSON output using `jq`, Ruby, and rexe.
- **[Ruby Library Examples](examples/ruby-library-examples.md)** – Using cov-loupe from Ruby: basic usage, filtering and analysis, and custom formatting.

## In Your Test Runs and CI

- **[Test Run Integration](examples/test-run-integration.md)** – Report the lowest-coverage files at the end of every test run.
- **[CI/CD Integration](examples/ci-cd-integration.md)** – Coverage thresholds in GitHub Actions and GitLab CI, stale-coverage checks, and custom success predicates.
- **[Advanced Usage Examples](examples/advanced-usage-examples.md)** – Directory-level coverage analysis, and coverage checks for the files changed in a code review.

## Example Scripts

The `examples/` directory contains runnable scripts:

- **[filter_and_table_demo.rb](https://github.com/keithrbennett/cov-loupe/blob/main/examples/filter_and_table_demo.rb)** - Filter and format coverage data ([sample output](https://github.com/keithrbennett/cov-loupe/blob/main/examples/filter_and_table_demo-output.md))
- **[success_predicates](../examples/success_predicates.md)** - Custom coverage policy examples
- **[Coverage Delta Tracking recipe in the Library API Guide](LIBRARY_API.md#coverage-delta-tracking)**

## Related Documentation

- [CLI Usage Guide](CLI_USAGE.md) - Complete command reference
- [Library API Guide](LIBRARY_API.md) - Ruby API documentation
- [MCP Integration](MCP_INTEGRATION.md) - AI assistant setup
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
