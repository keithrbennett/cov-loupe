# Development Guide

[Back to main README](../../README.md)

> **Note:** Commands like `cov-loupe` assume the gem is installed globally. If not, substitute `bundle exec exe/cov-loupe`.

## Setup

```sh
git clone https://github.com/keithrbennett/cov-loupe.git
cd cov-loupe
bundle install
bin/setup-hooks  # optional: enable the tracked git hooks
gem build cov-loupe.gemspec && gem install cov-loupe-*.gem  # optional
cov-loupe --version  # verify it works
```

## Git Hooks

Hooks are optional and live in the tracked `hooks/` directory. `bin/setup-hooks` sets
`core.hooksPath` to that directory (nothing is copied into `.git/hooks`), so edits to a hook
take effect immediately. `pre-commit` and `pre-merge-commit` both run RuboCop and RSpec.

`core.hooksPath` replaces any global hooks path for this repository, and hooks previously copied
into `.git/hooks` are no longer used. CI runs the same checks regardless.

## Running Tests

```sh
bundle exec rspec
```

The suite must pass in any locale. CI also runs it under the C locale, where Ruby's default
external encoding is US-ASCII; to check a change that touches paths, arguments or output:

```sh
LANG=C LC_ALL=C bundle exec rspec
```

Specs see captured output as UTF-8 and pick the default output character mode as on a UTF-8
terminal; a spec that needs another encoding sets it explicitly (see `with_default_encodings` in
`spec/support/io_helpers.rb`).

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
module CovLoupe
  module Tools
    class MyTool < BaseTool
      tool_name 'my_tool'
      description 'What this tool does'
      input_schema(**input_schema_def)

      def self.call(path:, root: nil, coverage_file: nil, raise_on_stale: nil,
        error_mode: nil, output_chars: nil, server_context:)
        output_chars_sym = resolve_output_chars(output_chars, server_context)
        # A nil error_mode falls back to the server's --error-mode.
        with_error_handling('MyTool', error_mode: error_mode, server_context: server_context) do
          model = create_model(
            server_context: server_context,
            root: root,
            coverage_file: coverage_file,
            raise_on_stale: raise_on_stale
          )
          data = model.my_method_for(path)
          respond_json(data, output_chars: output_chars_sym)
        end
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
let(:server_context) { null_server_context } # from spec/support/mcp_helpers.rb
before { setup_mcp_response_stub }
```

## Adding Features

**CLI commands:** Add a command class under `lib/cov_loupe/commands/`, require it and register it in `CovLoupe::Commands::CommandFactory::COMMAND_MAP` (`command_factory.rb`), add its name to `CovLoupe::SUBCOMMANDS` (`lib/cov_loupe/subcommands.rb`; the CLI rejects names not listed there), optionally add an abbreviation to `CoverageCLI::SUBCOMMAND_ABBREVIATIONS`, describe it in the subcommand help in `OptionParserBuilder`, and add tests.

**MCP tools:** Create `*_tool.rb` in `lib/cov_loupe/tools/`, require it in `lib/cov_loupe/loaders/all_mcp.rb`, add it to `MCPServer::TOOLSET` in `mcp_server.rb`, and add an entry to `HelpTool::TOOL_GUIDE` (`spec/cov_loupe/mcp_server_spec.rb` checks that the two match). A tool that runs client-supplied code must override `executes_code?` to return true, so that it is registered only with `--allow-code-predicates`.

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

**RVM + Codex macOS:** `bundle exec rspec` fails in Codex's macOS sandbox with an RVM-managed Ruby; see [Troubleshooting](../user/TROUBLESHOOTING.md#running-the-test-suite-with-rvm-codex-macos) for workarounds.

**MCP server smoke test:**
```sh
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp
```

This confirms that the server launches and responds over stdio; it is not an exhaustive contract
test. See [MCP Integration — Error Responses](../user/MCP_INTEGRATION.md#error-responses) for
optional validation and error sanity checks and the full failure model.
