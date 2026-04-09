#!/usr/bin/env bash
# tests/copilot-detection.sh
#
# Table-driven test for the Copilot review detection logic in
# tests/copilot-detection.jq. Asserts each fixture under
# tests/fixtures/copilot-detection/ produces the expected
# (queued, detection_method) result.
#
# Run from the repo root: bash tests/copilot-detection.sh
#
# Exits 0 on all-pass, 1 on any failure or missing dependency.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
JQ_FILTER="$REPO_ROOT/tests/copilot-detection.jq"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures/copilot-detection"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq not found on PATH"
  exit 1
fi

if [ ! -f "$JQ_FILTER" ]; then
  echo "FAIL: jq filter not found: $JQ_FILTER"
  exit 1
fi

if [ ! -d "$FIXTURES_DIR" ]; then
  echo "FAIL: fixtures dir not found: $FIXTURES_DIR"
  exit 1
fi

PASSED=0
FAILED=0
TOTAL=0

# Collect fixtures into an array under nullglob so an empty fixtures dir
# (or a glob with no matches) errors with a clear message instead of
# iterating once over the literal "$FIXTURES_DIR/*.json" string and tripping
# `set -e` on the first jq call.
shopt -s nullglob
fixtures=("$FIXTURES_DIR"/*.json)
shopt -u nullglob

if [ ${#fixtures[@]} -eq 0 ]; then
  echo "FAIL: no fixtures found in $FIXTURES_DIR"
  exit 1
fi

# Expectations live next to each fixture in `_fixture_meta` so adding a new
# detection path means dropping a JSON file with no runner edits.
for fixture in "${fixtures[@]}"; do
  name=$(basename "$fixture" .json)
  TOTAL=$((TOTAL + 1))

  # Use explicit null check — `// empty` would collapse a real `false` expected
  # value to empty, which is exactly what the silent-no-op / race fixtures use.
  exp_queued=$(jq -r '._fixture_meta.expected_queued | if . == null then "MISSING" else tostring end' "$fixture")
  exp_method=$(jq -r '._fixture_meta.expected_detection_method | if . == null then "MISSING" else tostring end' "$fixture")

  if [ "$exp_queued" = "MISSING" ] || [ "$exp_method" = "MISSING" ]; then
    echo "FAIL $name: fixture is missing _fixture_meta.expected_queued or expected_detection_method"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Strip _fixture_meta before piping to the canonical filter — the production
  # input never carries it. Single pipeline outputs both fields space-separated
  # so `read` can split them; avoids the `echo "$result" | jq` pattern entirely.
  read -r got_queued got_method < <(jq 'del(._fixture_meta)' "$fixture" \
    | jq -rf "$JQ_FILTER" \
    | jq -r '"\(.queued) \(.detection_method)"')

  if [ "$got_queued" = "$exp_queued" ] && [ "$got_method" = "$exp_method" ]; then
    printf 'PASS %-20s queued=%s method=%s\n' "$name" "$got_queued" "$got_method"
    PASSED=$((PASSED + 1))
  else
    printf 'FAIL %-20s expected (queued=%s method=%s) got (queued=%s method=%s)\n' \
      "$name" "$exp_queued" "$exp_method" "$got_queued" "$got_method"
    FAILED=$((FAILED + 1))
  fi
done

echo "---"
echo "$PASSED passed / $FAILED failed / $TOTAL total"

[ "$FAILED" -eq 0 ]
