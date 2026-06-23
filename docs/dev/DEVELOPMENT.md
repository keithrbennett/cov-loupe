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

    def self.call(path:, root: nil, resultset: nil, raise_on_stale: nil,
      error_mode: 'log', server_context:)
      with_error_handling('MyTool', error_mode: error_mode) do
        model = create_model(
          server_context: server_context,
          root: root,
          resultset: resultset,
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

**CLI commands:** Add a command class under `lib/cov_loupe/commands/`, register it in `Commands::CommandFactory::COMMAND_MAP`, and add tests.

**MCP tools:** Create `*_tool.rb` in `lib/cov_loupe/tools/`, register in `mcp_server.rb`

**Coverage features:** Add core data operations to `CoverageModel` in `lib/cov_loupe/model/model.rb` or pure line-counting logic to `CoverageCalculator` in `lib/cov_loupe/coverage/coverage_calculator.rb`.

## Documentation Development

This project uses [MkDocs](https://www.mkdocs.org/) with the [Material theme](https://squidfunk.github.io/mkdocs-material/) for documentation.

### Installing MkDocs

**Recommended: Using a Virtual Environment (all platforms)**

Virtual environments isolate Python dependencies and don't require system-level permissions.

```bash
# Create virtual environment
python3 -m venv .venv-docs

# Activate it
source .venv-docs/bin/activate  # macOS/Linux
# Or on Windows: .venv-docs\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deactivate when done (optional)
deactivate
```

Note: Virtual environment directories (`.venv/`, `.venv-*/`, `venv/`) are already in `.gitignore`.

**Alternative: System/User Installation**

**macOS:**
```bash
# Using Homebrew
brew install mkdocs
pip3 install mkdocs-material mkdocs-awesome-pages-plugin pymdown-extensions

# Or using pip only
pip3 install -r requirements.txt
```

**Linux (Ubuntu/Debian):**
```bash
# Install pip if needed
sudo apt update
sudo apt install python3-pip

# Install MkDocs and dependencies
pip3 install -r requirements.txt

# Add pip bin directory to PATH if mkdocs command not found
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Windows:**
```powershell
# Using pip (requires Python 3)
pip install -r requirements.txt

# Or install individually
pip install mkdocs mkdocs-material mkdocs-awesome-pages-plugin pymdown-extensions
```

### Building Documentation

```bash
# If using virtual environment, activate it first
source .venv-docs/bin/activate  # macOS/Linux
# Or on Windows: .venv-docs\Scripts\activate

# Build static site
mkdocs build

# Serve locally with live reload (opens at http://127.0.0.1:8000)
mkdocs serve
```

### Documentation Structure

- `docs/index.md` - Main landing page (derived from README.md)
- `docs/user/` - User-facing documentation (installation, usage, examples)
- `docs/dev/` - Developer documentation (architecture, contributing)
- `mkdocs.yml` - MkDocs configuration and navigation structure

### Adding Documentation

1. Create or edit markdown files in the `docs/` directory
2. Add new pages to the `nav` section in `mkdocs.yml`
3. Test locally with `mkdocs serve`
4. Commit changes along with your code changes

### Troubleshooting MkDocs

**Command not found after pip install:**
- Ensure pip's bin directory is in your PATH
- macOS: `export PATH="$HOME/Library/Python/3.x/bin:$PATH"`
- Linux: `export PATH="$HOME/.local/bin:$PATH"`
- Or run via Python: `python3 -m mkdocs serve`

## Troubleshooting

**RVM + Codex macOS:** Currently not possible for Codex to run rspec when running on macOS with rvm-managed rubies - see [Troubleshooting](../user/TROUBLESHOOTING.md)

**MCP server testing:**
```sh
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"version","arguments":{}}}' | cov-loupe -m mcp
```
