# Output Character Mode

[Back to main README](../../index.md)

This document describes the architectural decision for implementing a global output character mode that controls ASCII vs Unicode output across CLI and MCP interfaces.

## Status

Accepted

## Context

cov-loupe outputs data in multiple formats across two interfaces:

1. **CLI mode**: Human users read terminal output including tables, error messages, and formatted coverage reports
2. **MCP server mode**: AI agents receive JSON responses containing coverage data and metadata

### The Problem

Modern projects often contain file paths with Unicode characters (e.g., accented characters, non-Latin scripts). The original implementation used Unicode characters throughout:

- Table borders using box-drawing characters (│ ─ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼)
- Source code markers (✓ for covered, X for uncovered)
- Error messages with file paths preserved as-is

This caused issues in environments that don't support Unicode:

- Windows terminals with legacy encoding
- CI/CD systems with ASCII-only terminals
- Piped output to files or tools expecting ASCII
- Legacy systems without UTF-8 support

Users experienced garbled output, corrupted tables, and unreadable error messages.

### Requirements

- **ASCII mode**: Must produce ASCII-only output (0-127 characters) when requested
- **Fancy mode**: Should use Unicode characters for enhanced readability when supported
- **Auto-detection**: Default mode should intelligently choose based on environment
- **MCP integration**: MCP tools must support the same output modes as CLI
- **Comprehensive coverage**: All output channels must respect the mode setting
- **Backward compatibility**: Existing behavior (Unicode) should remain the default when supported

### Considered Approaches

1. **Separate ASCII formatters**: Create duplicate formatter implementations for ASCII output
   - Too much code duplication
   - Maintenance burden (two implementations of each formatter)

2. **Post-process all output**: Apply ASCII conversion after formatting
   - Inefficient (convert entire formatted output)
   - Could corrupt already-encoded data (JSON structure)

3. **Centralized conversion with charsets**: Define separate charsets and convert at formatting time
   - Clean separation of concerns
   - Efficient (convert only what's displayed)
   - Consistent across all formatters

## Decision

We implemented **global output character mode** with centralized conversion using charset definitions.

### Mode Options

Three modes are available:
- `default`: Auto-detects terminal UTF-8 support at runtime → fancy if supported, otherwise ASCII
- `fancy`: Forces Unicode output with box-drawing characters and fancy markers
- `ascii`: Forces ASCII-only output with transliteration fallback to `?` for unknown characters

### Configuration

- **CLI**: `-O/--output-chars MODE` flag (case-insensitive, short forms `d|f|a`)
- **MCP**: Optional `output_chars` parameter in tool requests (overrides server default)
- **No environment variable**: Intentionally omitted to keep configuration simple and explicit

### Core Implementation

The `OutputChars` module (`lib/cov_loupe/output_chars.rb`) provides:

```ruby
module OutputChars
  # Mode resolution
  def self.resolve_mode(mode)
    return :fancy if mode == :fancy
    return :ascii if mode == :ascii
    # default: detect terminal UTF-8 support
    stdout_utf8? ? :fancy : :ascii
  end

  # Character conversion using transliteration map
  def self.convert(text, mode)
    return text unless mode == :ascii
    text.chars.map { |c| TRANSLITERATIONS[c] || c.ascii_only? ? c : '?' }.join
  end

  # Charset selection
  def self.charset_for(mode)
    mode == :fancy ? FANCY_CHARSET : ASCII_CHARSET
  end
end
```

### Transliteration Strategy

Instead of a generic library (like `ActiveSupport::Multibyte`), we use an internal `TRANSLITERATIONS` hash mapping common characters to ASCII equivalents:

- Accented Latin characters (á → a, é → e, ñ → n, etc.)
- Symbols and punctuation (→ ->, — --, © (C), etc.)
- Box-drawing characters (│ → |, ─ → -, ┌ → +, etc.)

Characters without defined mappings fall back to `?` to maintain ASCII-only output.

### Formatter Integration

All formatters respect the `output_chars` parameter:

1. **JSON**: Uses `JSON.generate(..., ascii_only: true)` in ASCII mode
2. **YAML**: Post-processes through `OutputChars.convert`
3. **AmazingPrint**: Post-processes through `OutputChars.convert`
4. **Tables**: Uses appropriate charset (`OutputChars.charset_for`) and converts cell contents
5. **Source**: Uses ASCII-safe markers and converts source code.
   Covered lines use `+` instead of `✓`; the uncovered marker `X` stays unchanged.

### Error Message Integration

- CLI error handlers convert messages via `OutputChars.convert`
- Staleness error messages convert file paths via `convert_path` lambda
- Option parser errors converted before display
- Backtrace lines converted in debug mode

### Scope of Conversion

**Converted in ASCII mode:**
- All CLI error messages and option parser errors
- Staleness error messages and file paths
- Command literal strings (via `convert_text` helper in BaseCommand)
- MCP tool JSON responses (via `respond_json` with `ascii_only: true`)
- All formatted output (tables, source, JSON, YAML)

**Not converted in ASCII mode:**
- **Log files**: Preserved in original encoding for debugging fidelity. Log files are system/debugging artifacts, not user-facing output. Converting would lose exact file paths and error details needed for troubleshooting, create inconsistency between logged paths and actual filesystem paths, and provides no user value since logs are developer artifacts.
- **Gem post-install message**: Intentionally left unchanged per requirements

## Consequences

### Positive

1. **Broad compatibility**: Works in any terminal environment, including legacy systems
2. **Better UX**: Fancy mode provides enhanced readability when Unicode is supported
3. **Auto-detection**: Default mode adapts to environment without user configuration
4. **Comprehensive coverage**: All output channels respect the mode setting
5. **MCP parity**: CLI and MCP interfaces have identical behavior
6. **No dependencies**: Internal transliteration map avoids external dependencies
7. **Consistent behavior**: Single source of truth for character conversion

### Negative

1. **Complexity**: Additional configuration option and conversion logic to maintain
2. **Transliteration coverage**: Not all Unicode characters have mappings (falls back to `?`)
3. **Performance**: Conversion overhead for every output operation (minimal in practice)
4. **Test burden**: Comprehensive tests needed across all formatters and modes

### Trade-offs

- **Internal vs external transliteration**: Internal map is less comprehensive but avoids dependencies and keeps behavior predictable
- **Charset vs post-processing**: Charsets are cleaner but require formatter awareness; post-processing is simpler but can corrupt structured data
- **Auto-detection vs explicit default**: Auto-detection is more convenient but less predictable; explicit default is clearer but requires configuration

### Future Constraints

- Any new formatters must respect `output_chars` parameter
- New output channels (e.g., HTML) need ASCII mode support
- Transliteration map must be maintained as new characters are encountered
- Log files must never be converted (documented design decision)

## Implementation Notes

### Mode Precedence

1. Explicit mode parameter (CLI flag or MCP tool parameter)
2. Server default (for MCP)
3. Built-in default (auto-detect UTF-8 support)

### Performance Considerations

- Conversion only applies in ASCII mode (fancy mode is a no-op)
- Transliteration map lookup is O(1) per character
- JSON `ascii_only: true` is optimized by the json gem
- Overall performance impact is negligible (< 1ms for typical outputs)

### Testing Strategy

Comprehensive test coverage ensures correctness:

- Mode resolution and normalization tests
- Formatter tests for both ASCII and fancy modes
- CLI option parsing tests for `--output-chars` flag
- MCP tool output mode tests
- Staleness error message tests with Unicode file paths
- Integration tests across all subcommands with Unicode file names

## References

- Core implementation: `lib/cov_loupe/output_chars.rb`
- Configuration: `lib/cov_loupe/config/app_config.rb`, `lib/cov_loupe/config/option_normalizers.rb`
- Formatters:
    - `lib/cov_loupe/formatters/formatters.rb` (JSON, YAML, AmazingPrint)
    - `lib/cov_loupe/formatters/table_formatter.rb` (tables)
    - `lib/cov_loupe/formatters/source_formatter.rb` (source code)
- Error handling: `lib/cov_loupe/cli.rb`, `lib/cov_loupe/errors/error_handler.rb`
- MCP integration: `lib/cov_loupe/base_tool.rb`, `lib/cov_loupe/tools/*.rb`
- CLI option parsing: `lib/cov_loupe/config/option_parser_builder.rb`
- Tests:
    - `spec/cov_loupe/output_chars_spec.rb`
    - `spec/cov_loupe/formatters/*_spec.rb`
    - `spec/cov_loupe/cli/cli_output_chars_spec.rb`
    - `spec/cov_loupe/tools/*_spec.rb`
