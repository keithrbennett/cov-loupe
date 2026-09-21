# CLI Examples

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../index.md)

> For brevity, these examples use `clp`, an alias to the demo fixture with partial coverage:
>
> `alias clp='cov-loupe -R docs/fixtures/demo_project'  # -R = --root`
>
> Swap `clp` for `cov-loupe` to run against your own project and coverage file.
> The demo fixture is a small Rails-like project in `docs/fixtures/demo_project` with intentional coverage gaps for testing `--tracked-globs`.
> Its coverage timestamp is deliberately set far in the future, so the outputs below are reproducible on a fresh clone.

## Coverage Analysis

**Detailed investigation:**
```bash
# See detailed hit counts
clp detailed lib/api/client.rb
clp d lib/api/client.rb

# Show full source with coverage markers
clp -s f summary lib/api/client.rb  # f = full
clp -s f s lib/api/client.rb

# Focus on uncovered areas only
clp -s u -n 5 uncovered lib/payments/refund_service.rb  # u = uncovered
clp -s u -n 5 u lib/payments/refund_service.rb
```

## Working with JSON Output

In addition to the benefit of JSON encoding being human readable, it can be used in single line commands to fetch and compute values using `jq`, Ruby's JSON library, or `rexe`.
Here are some examples:

**Parse and filter:**
```bash
# Files below threshold
clp -fJ list | jq '.files[] | select(.percentage < 80) | {file, coverage: .percentage}'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].select { |f| f["percentage"] < 80 }.each do |f|
    puts JSON.pretty_generate({file: f["file"], coverage: f["percentage"]})
  end
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ '
  self["files"].select { |f| f["percentage"] < 80 }.map do |f|
    {file: f["file"], coverage: f["percentage"]}
  end
'

# Count total uncovered lines
clp -fJ totals | jq '.lines.uncovered'

# Ruby alternative:
clp -fJ totals | ruby -r json -e '
  puts JSON.parse($stdin.read)["lines"]["uncovered"]
'

# Rexe alternative:
clp -fJ totals | rexe -ij -mb -op 'self["lines"]["uncovered"]'

# Group by directory (full path)
clp -fJ list |
  jq '.files
      | map(. + {dir: (.file | split("/") | .[0:-1] | join("/"))})
      | sort_by(.dir)
      | group_by(.dir)
      | map({dir: .[0].dir, avg: (map(.percentage) | add / length)})'

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  grouped = JSON.parse($stdin.read)["files"]
    .map { |f| f.merge("dir" => File.dirname(f["file"])) }
    .group_by { |f| f["dir"] }
    .map { |dir, files|
      avg = files.sum { |f| f["percentage"] } / files.size
      {dir: dir, avg: avg}
    }
  puts JSON.pretty_generate(grouped)
'

# Rexe alternative:
clp -fJ list | rexe -ij -mb -oJ '
  self["files"]
    .map { |f| f.merge("dir" => File.dirname(f["file"])) }
    .group_by { |f| f["dir"] }
    .map { |dir, files|
      avg = files.sum { |f| f["percentage"] } / files.size
      {dir: dir, avg: avg}
    }
'
```

**Generate reports:**
```bash
# Create markdown table
echo "| Coverage | File |" > report.md
echo "|----------|------|" >> report.md
clp -fJ list | jq -r '.files[] | "| \(.percentage)% | \(.file) |"' >> report.md

# Ruby alternative:
clp -fJ list | ruby -r json -e '
  JSON.parse($stdin.read)["files"].each do |f|
    puts "| #{f["percentage"]}% | #{f["file"]} |"
  end
' >> report.md

# Rexe alternative:
clp -fJ list | rexe -ij -mb '
  self["files"].each { |f| puts "| #{f["percentage"]}% | #{f["file"]} |" }
' >> report.md

# Export for spreadsheet
clp -fJ list | jq -r '.files[] | [.file, .percentage] | @csv' > coverage.csv

# Ruby alternative:
clp -fJ list | ruby -r json -r csv -e '
  JSON.parse($stdin.read)["files"].each do |f|
    puts CSV.generate_line([f["file"], f["percentage"]]).chomp
  end
' > coverage.csv

# Rexe alternative:
clp -fJ list | rexe -r csv -ij -mb '
  self["files"].each { |f| puts CSV.generate_line([f["file"], f["percentage"]]).chomp }
' > coverage.csv
```
