#!/usr/bin/env bash
# State schema v1/v2 fixture tests
# Validates that jq can parse both schema versions and extract issue data correctly.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ABORT: jq not found — install jq to run state schema tests"; exit 1; }

FIXTURE_DIR="$(dirname "$0")/fixtures/state-schema"
[ -d "$FIXTURE_DIR" ] || { echo "ABORT: fixture directory not found — $FIXTURE_DIR"; exit 1; }

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

# --- v2 hitl-declined (HITL gate: operator chose No, skip Copilot review) ---
F="$FIXTURE_DIR/v2-hitl-declined.json"
check "$F" "hitl-declined: phase"              '.phase'                              "pr_open"
check "$F" "hitl-declined: exit_reason"        '.review.copilot.exit_reason'         "hitl_declined"
check "$F" "hitl-declined: hitl_decision"      '.review.copilot.hitl_decision'       "declined"
check "$F" "hitl-declined: hitl_confirmed_at"  '.review.copilot.hitl_confirmed_at'   "null"
check "$F" "hitl-declined: loops_run"          '.review.copilot.loops_run'           "0"
check "$F" "hitl-declined: total_loops_run"    '.review.total_loops_run'             "0"
check "$F" "hitl-declined: providers_completed empty" '.review.providers_completed | length' "0"
# Contract invariant: exit_reason=hitl_declined IMPLIES hitl_decision=declined
# (detects state-write inconsistency of the kind PR #38 found — the skip-path
#  writer must keep these two fields in sync, forever)
check "$F" "hitl-declined: contract invariant" '.review.copilot | select(.exit_reason == "hitl_declined") | .hitl_decision' "declined"

# --- v2 hitl-confirmed-approved (HITL gate: operator chose Yes, loop ran to approval) ---
F="$FIXTURE_DIR/v2-hitl-confirmed-approved.json"
check "$F" "hitl-confirmed: phase"             '.phase'                              "pr_open"
check "$F" "hitl-confirmed: exit_reason"       '.review.copilot.exit_reason'         "approved"
check "$F" "hitl-confirmed: hitl_decision"     '.review.copilot.hitl_decision'       "confirmed"
check "$F" "hitl-confirmed: hitl_confirmed_at" '.review.copilot.hitl_confirmed_at | length > 0' "true"
check "$F" "hitl-confirmed: loops_run"         '.review.copilot.loops_run'           "2"
check "$F" "hitl-confirmed: providers_done"    '.review.providers_completed | contains(["copilot"])' "true"

# --- v2 hitl-disabled-legacy-silent-no-op (gate off via config, legacy silent_no_op path) ---
F="$FIXTURE_DIR/v2-hitl-disabled-legacy-silent-no-op.json"
check "$F" "hitl-disabled: phase"             '.phase'                              "pr_open"
check "$F" "hitl-disabled: exit_reason"       '.review.copilot.exit_reason'         "silent_no_op"
check "$F" "hitl-disabled: hitl_decision"     '.review.copilot.hitl_decision'       "null"
check "$F" "hitl-disabled: hitl_confirmed_at" '.review.copilot.hitl_confirmed_at'   "null"
# v1/v2 compatibility: same fallback path as status.md all-mode footer
check "$F" "hitl-disabled: v2-compat check"   '(.review.copilot.exit_reason // .copilot.exit_reason)' "silent_no_op"

# --- goal-run state (Phase G milestone orchestrator) ---
F="$FIXTURE_DIR/goal-run.json"
check "$F" "goal-run: schema_version"          '.schema_version'                       "1"
check "$F" "goal-run: milestone.number"        '.milestone.number'                     "10"
check "$F" "goal-run: autonomy enum"           '.autonomy as $a | (["red-only","unattended","attended"] | index($a)) != null' "true"
check "$F" "goal-run: worklist length"         '.worklist | length'                    "4"
check "$F" "goal-run: issue done status"       '.issues["67"].status'                  "done"
check "$F" "goal-run: issue needs_human"       '.issues["68"].status'                  "needs_human"
check "$F" "goal-run: done copilot_exit ok"    '.issues["67"].copilot_exit as $e | (["approved","no_actionable_feedback"] | index($e)) != null' "true"
check "$F" "goal-run: needs_human exit ok"     '.issues["68"].copilot_exit as $e | (["silent_no_op","max_loops","tests_failed","hitl_declined"] | index($e)) != null' "true"

echo "---"
echo "$PASS passed / $FAIL failed / $TOTAL total"
[ "$FAIL" -eq 0 ] || exit 1
