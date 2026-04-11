#!/usr/bin/env bash
# Verify that every Layer C exit_reason enum value is present in all three
# authoritative locations: config.md (canonical definition), ship.md (schema
# templates + prose), and review.md (schema template + exit conditions).
#
# This is the PR #24 class of ripple defense: when a future change adds a new
# exit_reason value (or removes one), CI fails unless all three files are
# updated together. To extend the enum, update both the ENUM_VALUES array
# below AND the three command files in the same commit.
#
# Not a substitute for careful review — this is a safety net for the most
# common ripple class (adding/renaming an enum token and missing one of the
# three authoritative locations).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ENUM_VALUES=(
  "approved"
  "no_actionable_feedback"
  "max_loops"
  "tests_failed"
  "silent_no_op"
  "hitl_declined"
)

FILES=(
  "$REPO_ROOT/commands/config.md"
  "$REPO_ROOT/commands/ship.md"
  "$REPO_ROOT/commands/review.md"
)

FAIL=0
for v in "${ENUM_VALUES[@]}"; do
  for f in "${FILES[@]}"; do
    if ! grep -q "$v" "$f"; then
      echo "FAIL: exit_reason value '$v' not found in $(basename "$f")"
      FAIL=$((FAIL + 1))
    fi
  done
done

if [ "$FAIL" -eq 0 ]; then
  echo "OK: all ${#ENUM_VALUES[@]} exit_reason values present in all ${#FILES[@]} files"
  echo "    (config.md, ship.md, review.md)"
else
  echo ""
  echo "To fix: ensure every value in ENUM_VALUES at tests/enum-sync-check.sh"
  echo "appears in all three files (config.md Layer C list, ship.md schema"
  echo "template + prose, review.md schema template + exit conditions)."
  exit 1
fi
