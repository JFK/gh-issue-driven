#!/usr/bin/env bash
# State schema v1/v2 fixture tests
# Validates that jq can parse both schema versions and extract issue data correctly.
set -euo pipefail

FIXTURE_DIR="$(dirname "$0")/fixtures/state-schema"
PASS=0; FAIL=0; TOTAL=0

check() {
  local file="$1" desc="$2" expr="$3" expected="$4"
  TOTAL=$((TOTAL + 1))
  local got
  got=$(jq -r "$expr" "$file" 2>/dev/null) || got="ERROR"
  if [ "$got" = "$expected" ]; then
    printf "PASS %-45s %s\n" "$desc" "$got"
    PASS=$((PASS + 1))
  else
    printf "FAIL %-45s expected=%s got=%s\n" "$desc" "$expected" "$got"
    FAIL=$((FAIL + 1))
  fi
}

# --- v1 single issue (no issues array) ---
F="$FIXTURE_DIR/v1-single.json"
check "$F" "v1: schema_version"           '.schema_version'           "1"
check "$F" "v1: issue_number"             '.issue_number'             "39"
check "$F" "v1: issue_title exists"       '.issue_title | length > 0' "true"
check "$F" "v1: no issues array"          '.issues // "absent"'       "absent"
# v1→v2 compat: synthesize issues array
check "$F" "v1: synth issues[0].number"   '[{number: .issue_number, title: .issue_title, url: .issue_url}] | .[0].number' "39"

# --- v2 single issue ---
F="$FIXTURE_DIR/v2-single.json"
check "$F" "v2-single: schema_version"    '.schema_version'           "2"
check "$F" "v2-single: issues count"      '.issues | length'          "1"
check "$F" "v2-single: issues[0].number"  '.issues[0].number'        "39"
check "$F" "v2-single: is_batch"          '.is_batch'                 "false"
check "$F" "v2-single: v1 alias match"    '.issue_number == .issues[0].number' "true"
check "$F" "v2-single: v1 title match"    '.issue_title == .issues[0].title'   "true"

# --- v2 batch ---
F="$FIXTURE_DIR/v2-batch.json"
check "$F" "v2-batch: schema_version"     '.schema_version'           "2"
check "$F" "v2-batch: issues count"       '.issues | length'          "3"
check "$F" "v2-batch: issues[0].number"   '.issues[0].number'        "4"
check "$F" "v2-batch: issues[2].number"   '.issues[2].number'        "20"
check "$F" "v2-batch: is_batch"           '.is_batch'                 "true"
check "$F" "v2-batch: v1 alias = first"   '.issue_number == .issues[0].number' "true"
check "$F" "v2-batch: all have labels"    '[.issues[] | .labels | length > 0] | all' "true"
check "$F" "v2-batch: branch has batch"   '.branch | contains("batch")' "true"
# Compose Closes lines
check "$F" "v2-batch: closes lines"       '[.issues[].number | "Closes #\(.)"] | join("\n")' "$(printf 'Closes #4\nCloses #12\nCloses #20')"

echo "---"
echo "$PASS passed / $FAIL failed / $TOTAL total"
[ "$FAIL" -eq 0 ] || exit 1
