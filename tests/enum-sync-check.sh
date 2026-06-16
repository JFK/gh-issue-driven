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
#     review.md (schema template + exit conditions + stay-as-draft list).
#     ship.md forwards to review.md but no longer owns the loop state.
#   - hitl_decision: operator decision from the HITL gate. Enumerated in
#     config.md:23 and the review.md schema template.
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

# autonomy level: the --autonomous=<level> flag enum, mirrored from
# goal.autonomy. Must stay identical across objective.md (the source of truth)
# and the delegated commands that parse the flag (start.md, ship.md, review.md).
# Added with #74 (--autonomous HITL suppression).
AUTONOMY_LEVEL_VALUES=(
  "red-only"
  "unattended"
  "attended"
)

FILES=(
  "$REPO_ROOT/commands/config.md"
  "$REPO_ROOT/commands/review.md"
)

# The autonomy enum lives in a different set of files than exit_reason /
# hitl_decision: it is defined in objective.md and consumed by start.md + ship.md
# (which forwards --autonomous) + review.md (which now parses --autonomous and
# writes hitl_decision). config.md does not parse the flag, so it is not checked.
AUTONOMY_FILES=(
  "$REPO_ROOT/commands/objective.md"
  "$REPO_ROOT/commands/start.md"
  "$REPO_ROOT/commands/ship.md"
  "$REPO_ROOT/commands/review.md"
)

PASS=0
FAIL=0

# check_enum reads the file list from the global CHECK_FILES array (set by the
# caller before each invocation) so different enums can be checked against
# different file sets without a nameref (portable to bash 3.x / macOS).
check_enum() {
  local enum_name="$1"
  shift
  local values=("$@")
  for v in "${values[@]}"; do
    for f in "${CHECK_FILES[@]}"; do
      local base
      base="$(basename "$f")"
      if grep -Fq -- "$v" "$f"; then
        printf "OK   %-22s %-24s in %s\n" "$enum_name" "$v" "$base"
        PASS=$((PASS + 1))
      else
        printf "FAIL %-22s %-24s missing in %s\n" "$enum_name" "$v" "$base"
        FAIL=$((FAIL + 1))
      fi
    done
  done
}

CHECK_FILES=("${FILES[@]}")
check_enum "exit_reason"   "${EXIT_REASON_VALUES[@]}"
check_enum "hitl_decision" "${HITL_DECISION_VALUES[@]}"

CHECK_FILES=("${AUTONOMY_FILES[@]}")
check_enum "autonomy_level" "${AUTONOMY_LEVEL_VALUES[@]}"

echo "---"
echo "$PASS in sync / $FAIL drifted / $((PASS + FAIL)) total"

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "To fix: ensure every value in EXIT_REASON_VALUES / HITL_DECISION_VALUES"
  echo "at tests/enum-sync-check.sh appears in all files listed in FILES (config.md"
  echo "Layer C list, review.md schema template + exit conditions + stay-as-draft"
  echo "list). For AUTONOMY_LEVEL_VALUES, ensure every level appears in all"
  echo "AUTONOMY_FILES (objective.md, start.md, ship.md, review.md). Also manually review"
  echo "commands/status.md for any display-level updates the mechanical check"
  echo "does not cover."
  exit 1
fi
