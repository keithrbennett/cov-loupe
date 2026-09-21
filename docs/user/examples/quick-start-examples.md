# Quick Start Examples

[Back to Examples](../EXAMPLES.md) | [Back to main README](../../index.md)

> For brevity, these examples use `clp`, an alias to the demo fixture with partial coverage:
>
> `alias clp='cov-loupe -R docs/fixtures/demo_project'  # -R = --root`
>
> Swap `clp` for `cov-loupe` to run against your own project and coverage file.
> The demo fixture is a small Rails-like project in `docs/fixtures/demo_project` with intentional coverage gaps for testing `--tracked-globs`.
> Its coverage timestamp is deliberately set far in the future, so the outputs below are reproducible on a fresh clone.

## View All Coverage

```bash
# Default: show all files, best coverage first
clp
clp l

# Show files with worst coverage first
clp -o a list  # -o = --sort-order, a = ascending
clp -o a l

# Export to JSON for processing
clp -fJ list > coverage-report.json
clp -fJ l > coverage-report.json
```

## Check Specific File

```bash
# Quick summary
clp summary app/models/order.rb
clp s app/models/order.rb

# See which lines aren't covered
clp uncovered app/controllers/orders_controller.rb
clp u app/controllers/orders_controller.rb

# View uncovered code with context
clp -s u -n 3 uncovered app/controllers/orders_controller.rb  # -s = --source (u = uncovered), -n = --context-lines
clp -s u -n 3 u app/controllers/orders_controller.rb
```

## Find Coverage Gaps

```bash
# Files with worst coverage (account for header/footer)
clp list | tail -12
clp l | tail -12

# Only show files below 80%
clp -fJ list | jq '.files[] | select(.percentage < 80)'
clp -fJ l | jq '.files[] | select(.percentage < 80)'

# Ruby alternative:
clp -fJ l | ruby -r json -e '
  JSON.parse($stdin.read)["files"].select { |f| f["percentage"] < 80 }.each do |f|
    puts JSON.pretty_generate(f)
  end
'

# Rexe alternative:
clp -fJ l | rexe -ij -mb -oJ 'self["files"].select { |f| f["percentage"] < 80 }'

# Check specific directory
clp -g "lib/payments/**/*.rb" list  # -g = --tracked-globs
clp -g "lib/payments/**/*.rb" l
```
