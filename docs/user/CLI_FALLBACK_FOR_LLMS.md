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

- Run it as `cov-loupe <subcommand> ... -fJ` (or `bundle exec exe/cov-loupe ...` from a
  cov-loupe checkout), with the subcommand first and options after it. -fJ gives the same
  JSON the MCP tools return. If it reports "MCP mode takes no subcommand", COV_LOUPE_OPTS
  selects MCP mode; run `cov-loupe -m cli <subcommand> ...` instead.
- Carry over any root, coverage file, file globs, or staleness settings you were using:
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
| `path` | `file_*` | Positional `<path>` after the subcommand (after `--` if it starts with `-`) |
| `root` | All coverage tools | `-R`, `--root` |
| `coverage_file` | All coverage tools | `-c`, `--coverage-file` |
| `raise_on_stale` (boolean) | All coverage tools | `-S`, `--raise-on-stale` (takes a value, e.g. `-S true`) |
| `file_globs` (array) | `project_coverage`, `project_coverage_totals` | `-g`, `--file-globs` (comma-separated, e.g. `-g 'lib/**/*.rb,app/**/*.rb'`) |
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
- **Code predicates:** When started with `--allow-code-predicates`, the MCP server offers
  `project_validate`, which runs client-supplied Ruby; without the flag, the tool is not
  registered. The CLI's `validate` needs no flag, because you see and approve each command an
  agent runs. Keep this in mind when setting up your harness's permissions: although
  cov-loupe is mostly read-only, `validate` runs arbitrary Ruby, so a rule letting an agent
  run any `cov-loupe` command without asking also lets it run any Ruby. Allow only the
  subcommands the agent needs instead, such as `cov-loupe list` and `cov-loupe totals`.
- **Permission rules by subcommand:** options can follow the subcommand
  (`cov-loupe list -fJ`), so a prefix rule such as `Bash(cov-loupe list:*)` matches a
  subcommand with any options. After a subcommand other than `validate`, `-i`/`--inline` is
  an invalid option, and `-m`/`--mode` and `--[no-]allow-code-predicates` are rejected (as are
  `-h`, `-v` and `-p`), so such a rule cannot run Ruby or start the MCP server. It does allow
  every other option: `-l`/`--log-file` creates or appends to a
  file of the agent's choosing, and `-c`, `-R` and `-g` read any path. A prefix rule also
  covers one command, not a shell string: depending on your harness, `cov-loupe list && ...`
  may match it. A prefix rule is not a sandbox.

## Related Documentation

- [CLI Usage Guide](CLI_USAGE.md) - Complete CLI reference
- [MCP Integration](MCP_INTEGRATION.md) - MCP server setup and tool catalog
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
