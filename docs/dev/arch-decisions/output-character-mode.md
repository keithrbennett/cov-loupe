# Output Character Mode

[Back to main README](../../index.md)

This document describes the architectural decision for implementing a global output character mode that controls how cov-loupe draws its own decoration (Unicode or ASCII) across CLI and MCP interfaces.

## Status

Accepted. Amended on 2026-10-22: ASCII mode changes only cov-loupe's own decoration and never
alters data (see [Amendment](#amendment-ascii-mode-never-changes-data)).

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

(Since the Amendment, ASCII mode addresses only cov-loupe's own decoration in these
environments; it no longer guarantees ASCII-only output.)

### Requirements

- **ASCII mode**: Must draw cov-loupe's own decoration (table borders, the covered-line marker)
  with ASCII characters when requested, without changing data. (Originally: produce ASCII-only
  output, 0-127; see the Amendment.)
- **Fancy mode**: Should use Unicode characters for enhanced readability when supported
- **Auto-detection**: Default mode should intelligently choose based on environment
- **MCP integration**: MCP tools must support the same output modes as CLI
- **Comprehensive coverage**: Every output channel that draws decoration must take it from the mode
- **Backward compatibility**: Existing behavior (Unicode) should remain the default when supported

### Considered Approaches

1. **Separate ASCII formatters**: Create duplicate formatter implementations for ASCII output
   - Too much code duplication
   - Maintenance burden (two implementations of each formatter)

2. **Post-process all output**: Apply ASCII conversion after formatting
   - Inefficient (convert entire formatted output)
   - Could corrupt already-encoded data (JSON structure)
   - Alters user data along with the decoration (see the Amendment)

3. **Charsets for decoration**: Define a Unicode and an ASCII charset and choose one where the
   decoration is drawn
   - Clean separation of concerns: decoration changes, data does not
   - No conversion pass over output
   - Consistent across all formatters

## Decision

We implemented a **global output character mode** that selects a charset for cov-loupe's own
decoration.

### Mode Options

Three modes are available:
- `default`: Auto-detects terminal UTF-8 support at runtime → fancy if supported, otherwise ASCII
- `fancy`: Draws tables with box-drawing characters and marks covered lines with ✓
- `ascii`: Draws tables with `+ - |` and marks covered lines with `+`; JSON output escapes
  non-ASCII as `\uXXXX`. Data is never changed. (Originally: transliteration of all output with a
  `?` fallback; see the Amendment.)

### Configuration

- **CLI**: `-O/--output-chars MODE` flag (case-insensitive, short forms `d|f|a`)
- **MCP**: Optional `output_chars` parameter in tool requests (overrides server default)
- **No environment variable**: Intentionally omitted to keep configuration simple and explicit

### Core Implementation

The `OutputChars` module (`lib/cov_loupe/output_chars.rb`) provides, in outline (the real
`resolve_mode` and `ascii_mode?` also take an `io:` whose encoding decides `:default`, and
`resolve_mode` and `charset_for` raise `ArgumentError` for unknown modes):

```ruby
module OutputChars
  # Mode resolution
  def self.resolve_mode(mode)
    return :fancy if mode == :fancy
    return :ascii if mode == :ascii
    # default: detect terminal UTF-8 support
    stdout_utf8? ? :fancy : :ascii
  end

  # Whether ASCII decoration is in effect
  def self.ascii_mode?(mode) = resolve_mode(mode) == :ascii

  # Charset selection for table borders
  def self.charset_for(mode)
    mode == :fancy ? UNICODE_CHARSET : ASCII_CHARSET
  end
end
```

### Where the Mode Applies

1. **Tables** (`TableFormatter`, `CoverageTableFormatter`): borders come from
   `OutputChars.charset_for`. Cell contents, such as file paths, are shown as they are.
2. **Source output** (`SourceFormatter`): covered lines are marked `+` instead of `✓`; the
   uncovered marker is always `X`. Source lines are shown as they are.
3. **JSON** (`Formatters`, `BaseTool.respond_json`): `JSON.generate(..., ascii_only: true)`
   escapes non-ASCII as `\uXXXX`. That encodes the data without changing it.

**Not affected:** file paths, source lines, error messages, backtraces, YAML, AmazingPrint,
`inspect`, `puts` and `pretty_print` output, MCP error results, and log files. cov-loupe never
rewrites them; Ruby's own `inspect` escapes non-ASCII when the locale is not UTF-8.

## Amendment: ASCII mode never changes data

Date: 2026-10-22

The original design passed nearly all output through a transliteration step: accented Latin
letters and some symbols were converted, and every other non-ASCII character became `?`. That
destroyed user data (letters in file paths, source lines, method names and error messages) to
solve a problem that only concerns decoration, because the mode exists for terminals that cannot
draw fancy table borders. Limiting the replacement to a table of decorative characters was
considered and rejected, because it would still rewrite data that happens to contain them (a file
named `John’s – notes.rb` would become `John's - notes.rb`, a path that does not exist).

So ASCII mode now changes only what cov-loupe draws itself (table borders and the covered-line
marker), plus the lossless `\uXXXX` escaping of JSON. `OutputChars.convert` and its
transliteration table were removed.

Consequences of passing data through unchanged:

- ASCII mode no longer guarantees ASCII-only output. Users who need that can use JSON output in
  ASCII mode, whose successful payloads are escaped.
- Nothing scans or rewrites backtrace text any more. This also avoids a JRuby bug: some backtrace
  lines (from an `instance_eval` with a non-ASCII file name, or from a method with a non-ASCII
  name) carry stale encoding flags, so iterating their characters (as the old conversion did with
  `each_char`) can yield `nil` without end.
- Non-ASCII characters reach the output stream unchanged, as they always did in fancy mode.
  Writing them raises `Encoding::UndefinedConversionError` only if the stream transcodes to a
  non-UTF-8 encoding: when it was given one explicitly (for example with `IO#set_encoding`) or
  when `Encoding.default_internal` is set (for example with `RUBYOPT=-U` in a non-UTF-8 locale).
  By default Ruby's standard streams do not transcode and write the bytes as they are.
  (Separately, in a non-UTF-8 locale cov-loupe currently fails earlier, while reading a
  `coverage.json` that contains non-ASCII paths.)
- Table column widths use `String#length`, so wide (CJK) characters can misalign the right
  border. This applies in both modes.

## Consequences

### Positive

1. **Broad compatibility**: Table borders and markers render in terminals that cannot draw Unicode box-drawing characters
2. **Better UX**: Fancy mode provides enhanced readability when Unicode is supported
3. **Auto-detection**: Default mode adapts to environment without user configuration
4. **Data fidelity**: Paths, source lines and messages are never altered in any mode
5. **MCP parity**: CLI and MCP interfaces have identical behavior
6. **No dependencies and little code**: A charset per mode, no conversion pass

### Negative

1. **Complexity**: Additional configuration option to maintain
2. **Not ASCII-only**: Data containing non-ASCII characters still contains them in ASCII mode; only JSON escapes it
3. **Test burden**: Formatter tests are needed for both modes

### Trade-offs

- **Charset vs post-processing**: Charsets require formatter awareness; post-processing is simpler but corrupts structured data and alters user data
- **Auto-detection vs explicit default**: Auto-detection is more convenient but less predictable; explicit default is clearer but requires configuration

### Future Constraints

- Any new formatter that draws decoration must take it from the mode's charset
- New output channels (e.g., HTML) need ASCII mode support for their decoration
- Data must never be rewritten for display

## Implementation Notes

### Mode Precedence

1. Explicit mode parameter (CLI flag or MCP tool parameter)
2. Server default (for MCP)
3. Built-in default (auto-detect UTF-8 support)

### Performance Considerations

- The mode only selects characters for decoration; there is no conversion pass over output
- JSON `ascii_only: true` is optimized by the json gem

### Testing Strategy

Comprehensive test coverage ensures correctness:

- Mode resolution and normalization tests
- Formatter tests for both ASCII and fancy modes
- CLI option parsing tests for `--output-chars` flag
- MCP tool output mode tests
- Tests that paths, messages and other data are unchanged in ASCII mode

## References

- Core implementation: `lib/cov_loupe/output_chars.rb`
- Configuration: `lib/cov_loupe/config/app_config.rb`, `lib/cov_loupe/config/option_normalizers.rb`
- Formatters:
    - `lib/cov_loupe/formatters/formatters.rb` (JSON escaping)
    - `lib/cov_loupe/formatters/table_formatter.rb` and `lib/cov_loupe/coverage/coverage_table_formatter.rb` (tables)
    - `lib/cov_loupe/formatters/source_formatter.rb` (source code markers)
- MCP integration: `lib/cov_loupe/base_tool.rb`, `lib/cov_loupe/tools/*.rb`
- CLI option parsing: `lib/cov_loupe/config/option_parser_builder.rb`
- Tests:
    - `spec/cov_loupe/output_chars_spec.rb`
    - `spec/cov_loupe/formatters/*_spec.rb`
    - `spec/cov_loupe/cli/cli_output_chars_spec.rb`
    - `spec/cov_loupe/tools/*_spec.rb`
