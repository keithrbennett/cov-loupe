# Development Guide

[Back to main README](../index.md)

> **Note:** Commands like `cov-loupe` assume the gem is installed globally. If not, substitute `bundle exec exe/cov-loupe`.

## Setup

```sh
git clone https://github.com/keithrbennett/cov-loupe.git
cd cov-loupe
bundle install
gem build cov-loupe.gemspec && gem install cov-loupe-*.gem  # optional
cov-loupe --version  # verify it works
```

## Running Tests

```sh
bundle exec rspec
```

## Project-Specific Patterns

**All Ruby files start with:**
```ruby
# frozen_string_literal: true
```

**Error handling uses custom exceptions from `errors.rb`:**
```ruby
rescue Errno::ENOENT => e
  raise FileError.new("Coverage data not found: #{e.message}")
rescue JSON::ParserError => e
  raise CoverageDataError.new("Invalid coverage format: #{e.message}")
```

**MCP tools extend `BaseTool` and follow this pattern:**
```ruby
module CovLoupe::Tools
  class MyTool < BaseTool
    description 'What this tool does'
    input_schema(**input_schema_def)

    def self.call(path:, root: nil, coverage_file: nil, raise_on_stale: nil,
      error_mode: 'log', server_context:)
      with_error_handling('MyTool', error_mode: error_mode) do
        model = create_model(
          server_context: server_context,
          root: root,
          coverage_file: coverage_file,
          raise_on_stale: raise_on_stale
        )
        data = model.my_method_for(path)
        respond_json(model.relativize(data), name: 'my_tool_output.json')
      end
    end
  end
end
```

**Use test fixtures for consistency:**
```ruby
let(:project_root) { (FIXTURES_DIR / 'project1').to_s }
let(:coverage_dir) { File.join(project_root, 'coverage') }
```

**MCP tool tests need setup:**
```ruby
let(:server_context) { instance_double('ServerContext').as_null_object }
before { setup_mcp_response_stub }
```

## Adding Features

**CLI commands:** Add a command class under `lib/cov_loupe/commands/`, register it in `CovLoupe::Commands::CommandFactory::COMMAND_MAP`, and add tests.

**MCP tools:** Create `*_tool.rb` in `lib/cov_loupe/tools/`, register in `mcp_server.rb`

**Coverage features:** Add core data operations to `CoverageModel` in `lib/cov_loupe/model/model.rb` or pure line-counting logic to `CoverageCalculator` in `lib/cov_loupe/coverage/coverage_calculator.rb`.

## Documentation Development

This project uses [MkDocs](https://www.mkdocs.org/) with the [Material theme](https://squidfunk.github.io/mkdocs-material/) for documentation.

For the local docs server, dependency updates and audits, and publishing, see [Documentation Server](DOC_SERVER.md).

### Documentation Structure

- `docs/index.md` - Main landing page (derived from README.md)
- `docs/user/` - User-facing documentation (installation, usage, examples)
- `docs/dev/` - Developer documentation (architecture, contributing)
- `mkdocs.yml` - MkDocs configuration and navigation structure

### Adding Documentation

1. Create or edit markdown files in the `docs/` directory
2. Add new pages to the `nav` section in `mkdocs.yml`
3. Test locally with `bin/start-doc-server` and `bin/build-docs` (see [Documentation Server](DOC_SERVER.md))
4. Commit changes along with your code changes

## Troubleshooting

**RVM + Codex macOS:** Currently not possible for Codex to run rspec when running on macOS with rvm-managed rubies - see [Troubleshooting](../user/TROUBLESHOOTING.md)

**MCP server smoke test:**
```sh
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp
```

This confirms that the server launches and responds over stdio; it is not an exhaustive contract
test. See [MCP Integration — Error Responses](../user/MCP_INTEGRATION.md#error-responses) for
optional validation and error sanity checks and the full failure model.
