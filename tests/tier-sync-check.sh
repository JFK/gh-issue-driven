#!/usr/bin/env bash
# tier-sync-check.sh — the shared model-tier rubric (commands/config.md) is the
# reference; commands/review.md step 5b and commands/objective.md step 5b carry
# its executable one-line forms (a command never Reads another file to execute).
# This check asserts the thresholds, path pattern and tier names of the table
# still appear in each executable form, so an edit to one side cannot drift
# silently (issue #102; same spirit as jq-sync-check.sh).
#
# usage: bash tests/tier-sync-check.sh      (exit 0 = in sync, 1 = drifted)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

pass=0; fail=0
check() { # check <file> <description> <fixed-string needle>
  if grep -qF -- "$3" "$1"; then
    pass=$((pass + 1)); echo "ok    $1: $2"
  else
    fail=$((fail + 1)); echo "DRIFT $1: $2 — missing: $3"
  fi
}

CFG=commands/config.md; REV=commands/review.md; OBJ=commands/objective.md

# --- the reference table (config.md) ------------------------------------------
check "$CFG" "rubric heading"           '### Model-tier rubric (shared)'
check "$CFG" "docs-only signal"         'gate2.diff_scope_skip.docs_only_patterns'
check "$CFG" "trivial threshold"        '~20 changed lines'
check "$CFG" "risky path pattern"       'auth\|secret\|credential\|migration\|security'
check "$CFG" "wide file threshold"      '~10 files'
check "$CFG" "wide line threshold"      '~400 changed lines'
check "$CFG" "hardest row"              '| hardest |'
check "$CFG" "auto never fable"         'never resolves to `fable`'
check "$CFG" "fable alias"              '`fable` (Claude Fable 5.1, `claude-fable-5-1`)'

# --- review.md step 5b: executable diff signals --------------------------------
check "$REV" "docs-only signal"         'gate2.diff_scope_skip.docs_only_patterns'
check "$REV" "trivial threshold"        'total changed lines < ~20'
check "$REV" "risky path pattern"       'auth|secret|credential|migration|security'
check "$REV" "wide file threshold"      '> ~10 files'
check "$REV" "wide line threshold"      '> ~400 changed lines'
check "$REV" "docs-only → haiku"        '→ `haiku`'
check "$REV" "risky → opus"             '→ `opus`'
check "$REV" "otherwise → sonnet"       '→ `sonnet`'
check "$REV" "alias list incl. fable"   '`haiku|sonnet|opus|fable|<id>`'
check "$REV" "auto never fable"         '`auto` never resolves to `fable`'

# --- objective.md step 5b: scope → tier line and the effort fallback -----------
check "$OBJ" "scope → tier line"        'docs/trivial → haiku, normal → sonnet, risky/wide → opus, never fable'
check "$OBJ" "effort fallback"          '`low` docs/small, `medium` normal, `high` risky or wide'
check "$OBJ" "review-model alias list"  'haiku | sonnet | opus | fable | <model id>'

# --- start.md step 12b: the issue-side mapping onto the same rows -------------
STA=commands/start.md
check "$STA" "12b heading"              '### 12b. Recommended model/effort profile (advisory)'
check "$STA" "hardest → fable/high"     '`hardest` → `fable`/`high`'
check "$STA" "risky → opus/high"        '`risky / wide` → `opus`/`high`'
check "$STA" "normal → opus/medium"     '`normal` → `opus`/`medium`'
check "$STA" "docs → sonnet/low"        '`docs-only / trivial` → `sonnet`/`low`'
check "$STA" "auto tiers, never fable"  '(`opus` / `opus` / `sonnet` / `haiku`; never `fable`)'

echo "$pass in sync / $fail drifted / $((pass + fail)) total"
[ "$fail" -eq 0 ]
