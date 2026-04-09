#!/usr/bin/env bash
# tests/jq-sync-check.sh
#
# Mechanically verifies that the inline jq filter in commands/ship.md step 13
# is byte-equivalent (in produced output, not necessarily in source text) to
# the canonical detect() function in tests/copilot-detection.jq.
#
# How: extracts the inline filter body between `# JQ_DETECT_FILTER_BEGIN` and
# `# JQ_DETECT_FILTER_END` sentinel comments in ship.md, builds a complete jq
# program from it, runs it against every fixture in tests/fixtures/copilot-detection/,
# and compares the result string against running tests/copilot-detection.jq on
# the same fixture.
#
# If they ever drift, this exits non-zero and prints the divergence per-fixture
# so the maintainer can see exactly what changed.
#
# Run from the repo root: bash tests/jq-sync-check.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SHIP_MD="$REPO_ROOT/commands/ship.md"
CANONICAL_JQ="$REPO_ROOT/tests/copilot-detection.jq"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures/copilot-detection"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq not found on PATH"
  exit 1
fi

for required in "$SHIP_MD" "$CANONICAL_JQ"; do
  if [ ! -f "$required" ]; then
    echo "FAIL: required file missing: $required"
    exit 1
  fi
done

if [ ! -d "$FIXTURES_DIR" ]; then
  echo "FAIL: fixtures dir missing: $FIXTURES_DIR"
  exit 1
fi

# Extract the inline filter body. The sentinels also appear in a prose
# explanation later in the file, so the state machine must take only the
# FIRST BEGIN..END run and stop. `&& !capture` keeps re-entering BEGINs
# from triggering, and `exit` terminates awk on the first matching END
# so the prose mention is never seen.
INLINE_BODY=$(awk '
  /# JQ_DETECT_FILTER_BEGIN/ && !capture { capture = 1; next }
  /# JQ_DETECT_FILTER_END/   && capture  { exit }
  capture { print }
' "$SHIP_MD")

if [ -z "$INLINE_BODY" ]; then
  echo "FAIL: could not extract inline filter from $SHIP_MD"
  echo "      expected sentinels: # JQ_DETECT_FILTER_BEGIN ... # JQ_DETECT_FILTER_END"
  exit 1
fi

# Compose into a runnable jq program. The canonical detect() returns
# { queued, detection_method }, but the inline filter returns just the
# detection_method string. To compare apples to apples, derive the same
# string from the canonical detect() output.
INLINE_PROGRAM="$INLINE_BODY"

PASSED=0
FAILED=0
TOTAL=0

for fixture in "$FIXTURES_DIR"/*.json; do
  name=$(basename "$fixture" .json)
  TOTAL=$((TOTAL + 1))

  # The fixture carries _fixture_meta for the other test runner. Strip it
  # via direct file → jq pipelines so the production-shape input is what
  # each filter sees. Avoids `echo "$VAR" | jq` (brittle on escape handling
  # and on JSON values that look like flags).
  inline_result=$(jq 'del(._fixture_meta)' "$fixture" | jq -r "$INLINE_PROGRAM")
  canonical_result=$(jq 'del(._fixture_meta)' "$fixture" | jq -rf "$CANONICAL_JQ" | jq -r .detection_method)

  if [ "$inline_result" = "$canonical_result" ]; then
    printf 'SYNC %-20s inline=%s canonical=%s\n' "$name" "$inline_result" "$canonical_result"
    PASSED=$((PASSED + 1))
  else
    printf 'DRIFT %-19s inline=%s canonical=%s\n' "$name" "$inline_result" "$canonical_result"
    FAILED=$((FAILED + 1))
  fi
done

echo "---"
echo "$PASSED in sync / $FAILED drifted / $TOTAL total"

if [ "$TOTAL" -eq 0 ]; then
  echo "FAIL: no fixtures found in $FIXTURES_DIR"
  exit 1
fi

if [ "$FAILED" -ne 0 ]; then
  echo
  echo "ship.md inline jq has drifted from tests/copilot-detection.jq."
  echo "Update both in the same commit, then re-run this check."
  exit 1
fi
