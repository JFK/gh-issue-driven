#!/usr/bin/env bash
# Verify that every Layer C enum value is present in ALL authoritative
# schema / prose locations across the command files. This is the PR #24
# class of ripple defense: when a future change adds or renames a Layer C
# enum token, CI fails unless every schema-bearing file is updated in the
# same commit.
#
# Current enums under sync-check:
#   - exit_reason: terminal state of the Copilot review loop, plus the
#     HITL decline path. Enumerated in config.md:23 (Layer C definition),
#     ship.md (schema template + exit conditions + stay-as-draft list),
#     review.md (schema template + exit conditions + stay-as-draft list).
#   - hitl_decision: operator decision from the HITL gate. Enumerated in
#     config.md:23 and the ship.md / review.md schema templates.
#
# Why status.md is NOT in FILES: status.md consumes these enums as display
# data, but only explicitly enumerates a subset (`silent_no_op` for the
# hint footer, `hitl_declined` for HITL display) — the other values flow
# through as raw field values without prose mention. Forcing status.md into
# the mechanical check would require adding prose for values that do not
# warrant it. When extending a Layer C enum, MANUALLY review status.md for
# any hint-footer / display-line updates that may be needed.
#
# To extend a Layer C enum:
#   1. Add the new value to the appropriate *_VALUES array below.
#   2. Update every file listed in FILES so the new value appears at
#      least once (the grep is literal-substring, not regex).
#   3. MANUALLY review commands/status.md for any display-level updates
#      that are not mechanically caught here.
#   4. If you introduce a brand-new Layer C enum, add a new *_VALUES
#      array and another `check_enum` call below.
#
# Not a substitute for careful review — this is a safety net for the
# common ripple class (add/rename an enum token and miss one file).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

EXIT_REASON_VALUES=(
  "approved"
  "no_actionable_feedback"
  "max_loops"
  "tests_failed"
  "silent_no_op"
  "hitl_declined"
)

HITL_DECISION_VALUES=(
  "confirmed"
  "declined"
)

FILES=(
  "$REPO_ROOT/commands/config.md"
  "$REPO_ROOT/commands/ship.md"
  "$REPO_ROOT/commands/review.md"
)

PASS=0
FAIL=0

check_enum() {
  local enum_name="$1"
  shift
  local values=("$@")
  for v in "${values[@]}"; do
    for f in "${FILES[@]}"; do
      local base
      base="$(basename "$f")"
      if grep -q "$v" "$f"; then
        printf "OK   %-22s %-24s in %s\n" "$enum_name" "$v" "$base"
        PASS=$((PASS + 1))
      else
        printf "FAIL %-22s %-24s missing in %s\n" "$enum_name" "$v" "$base"
        FAIL=$((FAIL + 1))
      fi
    done
  done
}

check_enum "exit_reason"   "${EXIT_REASON_VALUES[@]}"
check_enum "hitl_decision" "${HITL_DECISION_VALUES[@]}"

echo "---"
echo "$PASS in sync / $FAIL drifted / $((PASS + FAIL)) total"

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "To fix: ensure every value in EXIT_REASON_VALUES / HITL_DECISION_VALUES"
  echo "at tests/enum-sync-check.sh appears in all files listed in FILES (config.md"
  echo "Layer C list, ship.md schema template + prose, review.md schema template"
  echo "+ exit conditions). Also manually review commands/status.md for any"
  echo "display-level updates the mechanical check does not cover."
  exit 1
fi
