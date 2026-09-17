## MCP JSON Inputs

[Back to main README](../../docs/index.md)

This directory contains example JSON-RPC requests that can be sent to the MCP server over stdio.

Each file contains a single line of JSON (NDJSON-ready), so you can pipe it directly to the executable.

**Target Project:** These inputs are designed to work with the demo project located at `docs/fixtures/demo_project`.

The fixture's coverage timestamp is deliberately set far in the future, so the example responses are reproducible on a fresh clone.

### Running the Examples

From the repository root:

```sh
exe/cov-loupe -m mcp < examples/mcp-inputs/coverage_summary.json
exe/cov-loupe -m mcp < examples/mcp-inputs/uncovered_lines.json
```

If `cov-loupe` is installed globally and available on your `PATH`:

```sh
cov-loupe -m mcp < examples/mcp-inputs/coverage_summary.json
```

### Formatting Tips (jq and rexe)

You can use tools like [jq](https://github.com/jqlang/jq) or [rexe](https://github.com/keithrbennett/rexe) to format the JSON input and output, which is especially helpful for debugging.

**Pretty-print an input file:**

Using `jq`:
```sh
jq . examples/mcp-inputs/coverage_summary.json
```

Using Ruby:
```sh
ruby -r json -e '
  puts JSON.pretty_generate(JSON.parse(File.read("examples/mcp-inputs/coverage_summary.json")))
'
```

Using `rexe`:
```sh
rexe -f examples/mcp-inputs/coverage_summary.json -oJ
```

**Pretty-print the MCP server's JSON response (NDJSON):**

Using `jq`:
```sh
exe/cov-loupe -m mcp < examples/mcp-inputs/coverage_summary.json | jq .
```

Using Ruby:
```sh
exe/cov-loupe -m mcp < examples/mcp-inputs/coverage_summary.json | ruby -r json -e '
  puts JSON.pretty_generate(JSON.parse($stdin.read))
'
```

Using `rexe`:
```sh
exe/cov-loupe -m mcp < examples/mcp-inputs/coverage_summary.json | rexe -ml -ij -oJ
```
