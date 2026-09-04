#!/usr/bin/env bash
# Demo script for cov-loupe CLI subcommands and options
# Runs against the included fixture project at docs/fixtures/demo_project.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CLI=("bundle" "exec" "exe/cov-loupe")
PROJ="docs/fixtures/demo_project"
RESULTSET_DIR="." # directory containing .resultset.json under PROJ

run() {
  cat <<BANNER



-------------------------------------------------------------------------------
+ ${CLI[*]} $*
-------------------------------------------------------------------------------

BANNER
  "${CLI[@]}" "$@"

}

cat <<INTRO
== cov-loupe CLI demo ==

Note: Project root and coverage JSON file normally do not need to be specified.
We set --root here to use the docs/fixtures/demo_project nondefault location,
and later demonstrate a nondefault coverage file via the --coverage-file option.

Project root:     $PROJ
Resultset (dir):  $RESULTSET_DIR

INTRO

# 1) List all files (table)
run --root "$PROJ" list

# 2) List as JSON, descending sort
run --root "$PROJ" --sort-order descending --format json list

# 3) Summary for a file (text and JSON)
run --root "$PROJ" summary app/models/order.rb
run --root "$PROJ" --format json summary app/models/order.rb

# 4) Include source with summary (full and uncovered-only with context)
run --root "$PROJ" --source full summary app/models/order.rb
run --root "$PROJ" --source uncovered --context-lines 1 summary app/models/order.rb

# 5) Uncovered lines (text with source and JSON)
run --root "$PROJ" --source uncovered --context-lines 2 uncovered app/models/order.rb
run --root "$PROJ" --format json uncovered app/models/order.rb

# 6) Detailed per-line data (text and JSON), with source
run --root "$PROJ" --source full -C false detailed app/models/order.rb
run --root "$PROJ" --format json detailed app/models/order.rb

# 7) Raw lines array (JSON)
run --root "$PROJ" --format json raw app/models/order.rb

# 8) Using environment variable for a NONDEFAULT coverage file location
#    Copy the default coverage file into a simple alt directory to simulate a custom layout.
ALT_DIR="$PROJ/alt_resultset"
mkdir -p "$ALT_DIR"
cp -f "$PROJ/.resultset.json" "$ALT_DIR/.resultset.json"
echo 
echo "+ ${CLI[*]} --root $PROJ --coverage-file $PROJ/alt_resultset list"
"${CLI[@]}" --root "$PROJ" --coverage-file "$PROJ/alt_resultset" list

echo
echo "== Done =="

# Cleanup files created for the nondefault coverage file demo
rm -rf "$ALT_DIR"
