# CLI Fallback for LLMs

[Back to main README](../../README.md)

When the MCP server integration isn't working or available, LLMs can run the `cov-loupe` CLI
instead. Every MCP tool has a CLI equivalent that returns the same JSON payload when run with
`-fJ` (pretty JSON) or `-fj` (compact JSON). This page maps each tool and argument to its CLI
form.

## Sample Prompt for Users

If MCP isn't working, provide this prompt to your LLM:

```
The cov-loupe MCP server isn't available. Use the cov-loupe CLI instead:

- Run it as `cov-loupe -m cli -fJ <subcommand> ...` (or `bundle exec exe/cov-loupe ...`
  from a cov-loupe checkout). -m cli guards against COV_LOUPE_OPTS selecting MCP mode;
  -fJ gives the same JSON the MCP tools return.
- Carry over any root, coverage file, tracked globs, or staleness settings you were using:
  -R <root>, -c <coverage file>, -g <glob,glob>, -S true.
- Run `cov-loupe --help` for subcommands and options.
- Do not retry the MCP server, and do not read coverage.json yourself or estimate coverage
  from source or test files. All coverage data must come from cov-loupe output.
- validate prints no result; read its exit code (0 pass, 3 fail, 1 data error, 4 bad predicate).
- Say in your response that you used the CLI rather than the MCP server.
```

## MCP Tools and CLI Subcommands

| MCP tool | CLI equivalent | Notes |
|---|---|---|
| `project_coverage` | `list` (`l`) | `list` is the default subcommand. MCP defaults to JSON; the CLI defaults to a table. |
| `project_coverage_totals` | `totals` (`t`) | |
| `file_coverage_summary` | `summary <path>` (`s`) | |
| `file_coverage_detailed` | `detailed <path>` (`d`) | |
| `file_uncovered_lines` | `uncovered <path>` (`u`) | |
| `file_coverage_raw` | `raw <path>` (`r`) | |
| `project_validate` | `validate <file>` / `validate -i <code>` (`v`) | MCP returns `{"result": true/false}`; the CLI prints nothing and reports the result in its exit code. The MCP tool exists only when the server is started with `--allow-code-predicates`; the CLI always has it. |
| `version` | `--version` (`-v`) | MCP returns `CovLoupe version: <version>`; the CLI prints the bare version. |
| `help` | `--help` (`-h`) | MCP returns a JSON tool guide; the CLI prints usage text. |

## MCP Arguments and CLI Options

| MCP argument | Tools | CLI option |
|---|---|---|
| `path` | `file_*` | Positional `<path>` after the subcommand |
| `root` | All coverage tools | `-R`, `--root` |
| `coverage_file` | All coverage tools | `-c`, `--coverage-file` |
| `raise_on_stale` (boolean) | All coverage tools | `-S`, `--raise-on-stale` (takes a value, e.g. `-S true`) |
| `tracked_globs` (array) | `project_coverage`, `project_coverage_totals` | `-g`, `--tracked-globs` (comma-separated, e.g. `-g 'lib/**/*.rb,app/**/*.rb'`) |
| `sort_order` | `project_coverage` | `-o`, `--sort-order` |
| `format` | `project_coverage` | `-f`, `--format` (use `-fJ` or `-fj` for JSON) |
| `code` / `file` | `project_validate` | `validate -i <code>` / `validate <file>` |
| `error_mode` | All tools | `-e`, `--error-mode` |
| `output_chars` | All tools | `-O`, `--output-chars` |

Arguments the MCP server takes at startup rather than per call, such as `--log-file` and
`--allow-code-predicates`, have no per-call CLI counterpart; pass `-l`/`--log-file` on the
command line instead.

## Differences Between the Interfaces

- **Errors:** MCP returns `isError: true` with an `Error: <message>` text. The CLI prints the
  same message to stderr and exits nonzero. See [Error Handling](ERROR_HANDLING.md).
- **Output formats:** In MCP, only `project_coverage` accepts `format`; the other tools return
  JSON. The CLI accepts `-f` for every subcommand.
- **CLI-only options:** source display (`-s`/`--source`, `-n`/`--context-lines`), ANSI color
  (`-C`/`--color`), and resource lookup (`-p`/`--path-for`). The MCP server lists the same
  resources in its server instructions.

## Related Documentation

- [CLI Usage Guide](CLI_USAGE.md) - Complete CLI reference
- [MCP Integration](MCP_INTEGRATION.md) - MCP server setup and tool catalog
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
