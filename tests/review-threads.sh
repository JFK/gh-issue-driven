#!/usr/bin/env bash
# tests/review-threads.sh
#
# Validates the UNRESOLVED extraction jq filter used by the Copilot reply/resolve
# step (ship.md step 14.d, review.md step 5b). The filter selects review threads
# that are (a) unresolved AND (b) authored by the Copilot reviewer login, emitting
# {threadId, commentId, path, line, body} for each.
#
# The filter below is kept SEMANTICALLY in sync with the inline jq in ship.md /
# review.md. When you change one, change the other in the same commit.
#
# Run from the repo root: bash tests/review-threads.sh
# Exits 0 on all-pass, 1 on any failure or missing dependency.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
FIXTURE="$REPO_ROOT/tests/fixtures/review-threads/mixed.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq not found on PATH"
  exit 1
fi
if [ ! -f "$FIXTURE" ]; then
  echo "FAIL: fixture not found: $FIXTURE"
  exit 1
fi

# UNRESOLVED extraction filter (mirror of the inline filter in ship.md step 14.d)
FILTER='
  (.data.repository.pullRequest.reviewThreads.nodes // [])[]
  | select(.isResolved==false)
  | select((.comments.nodes[0].author.login // "") | test("[Cc]opilot"))
  | {threadId:.id, commentId:.comments.nodes[0].databaseId,
     path:.comments.nodes[0].path, line:.comments.nodes[0].line, body:.comments.nodes[0].body}'

PASS=0; FAIL=0; TOTAL=0
check() {
  local desc="$1" expr="$2" expected="$3"
  TOTAL=$((TOTAL + 1))
  local got
  got=$(jq -r "$expr" "$FIXTURE" 2>/dev/null) || got="ERROR"
  if [ "$got" = "$expected" ]; then
    printf 'PASS %-40s %s\n' "$desc" "$got"; PASS=$((PASS + 1))
  else
    printf 'FAIL %-40s expected=%s got=%s\n' "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}

# Exactly one thread survives: unresolved + Copilot-authored.
check "count of extracted threads"   "[$FILTER] | length"        "1"
check "extracted threadId"           "[$FILTER][0].threadId"     "RT_unresolved_copilot"
check "extracted commentId"          "[$FILTER][0].commentId"    "1001"
check "extracted path"               "[$FILTER][0].path"         "src/app.ts"
# Resolved Copilot thread is excluded.
check "resolved thread excluded"     "[$FILTER] | map(.threadId) | index(\"RT_resolved_copilot\") // \"absent\"" "absent"
# Human-authored unresolved thread is excluded.
check "human thread excluded"        "[$FILTER] | map(.threadId) | index(\"RT_unresolved_human\") // \"absent\"" "absent"

echo "---"
echo "$PASS passed / $FAIL failed / $TOTAL total"
[ "$FAIL" -eq 0 ]
