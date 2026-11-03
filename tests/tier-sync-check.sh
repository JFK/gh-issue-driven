#!/usr/bin/env bash
# tier-sync-check.sh — commands/config.md's "Model-tier rubric (shared)" table is
# the reference; commands/review.md step 5b, commands/objective.md step 5b and
# commands/start.md step 12b carry its executable one-line forms (a command never
# Reads another file to execute). The numeric thresholds and the risky path
# pattern are READ FROM the table and asserted in the executable forms; the tier
# names, the alias lists and the 12b class → model/effort mapping are pinned as
# fixed strings. Same spirit as jq-sync-check.sh (issue #102).
#
# usage: bash tests/tier-sync-check.sh      (exit 0 = in sync, 1 = drifted)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

CFG=commands/config.md; REV=commands/review.md; OBJ=commands/objective.md; STA=commands/start.md
pass=0; fail=0
check() { # check <file> <description> <fixed-string needle>
  if grep -qF -- "$3" "$1"; then
    pass=$((pass + 1)); echo "ok    $1: $2"
  else
    fail=$((fail + 1)); echo "DRIFT $1: $2 — missing: $3"
  fi
}

# --- read the reference values out of the config.md table ---------------------
table=$(awk '/^### Model-tier rubric \(shared\)/{p=1; next} p && /^### /{exit} p && /^\| (docs-only|normal|risky|hardest) /' "$CFG")
[ -n "$table" ] || { echo "DRIFT $CFG: rubric table rows not found under '### Model-tier rubric (shared)'"; exit 1; }
trivial=$(grep -oE 'fewer than ~[0-9]+ changed lines' <<<"$table" | grep -oE '[0-9]+' | head -1)
files=$(grep -oE 'more than ~[0-9]+ files' <<<"$table" | grep -oE '[0-9]+' | head -1)
lines=$(grep -oE 'more than ~[0-9]+ changed lines' <<<"$table" | grep -oE '[0-9]+' | head -1)
paths=$(grep -oE 'more than ~[0-9]+ repo paths' <<<"$table" | grep -oE '[0-9]+' | head -1)
# the table cell escapes the pipes for markdown (auth\|secret\|…); the executable forms use plain |
pattern=$(grep -oE 'auth[a-z|\\]+security' <<<"$table" | head -1 | sed 's/\\//g')
for v in trivial files lines paths pattern; do
  [ -n "${!v}" ] || { fail=$((fail + 1)); echo "DRIFT $CFG: could not read '$v' from the rubric table"; }
done
echo "reference ($CFG): trivial < ~${trivial:-?} lines · wide > ~${files:-?} files or > ~${lines:-?} lines · issue paths > ~${paths:-?} · pattern ${pattern:-?}"

# --- config.md: the reference itself ------------------------------------------
check "$CFG" "docs-only signal"          'gate2.diff_scope_skip.docs_only_patterns'
check "$CFG" "hardest row"               '| hardest |'
check "$CFG" "auto never fable"          'never resolves to `fable`'
check "$CFG" "fable alias"               '`fable` (Claude Fable 5.1, `claude-fable-5-1`)'

# --- review.md step 5b: executable diff signals --------------------------------
check "$REV" "docs-only signal"          'gate2.diff_scope_skip.docs_only_patterns'
check "$REV" "trivial threshold"         "total changed lines < ~${trivial}"
check "$REV" "risky path pattern"        "${pattern}"
check "$REV" "wide file threshold"       "> ~${files} files"
check "$REV" "wide line threshold"       "> ~${lines} changed lines"
check "$REV" "docs-only → haiku"         '→ `haiku`'
check "$REV" "risky → opus"              '→ `opus`'
check "$REV" "otherwise → sonnet"        '→ `sonnet`'
check "$REV" "alias list incl. fable"    '`haiku|sonnet|opus|fable|<id>`'
check "$REV" "auto never fable"          '`auto` never resolves to `fable`'
check "$REV" "valid values incl. fable"  '`auto`, `haiku`, `sonnet`, `opus`, `fable`, or a full model id'

# --- objective.md step 5b: scope → tier line and the effort fallback -----------
check "$OBJ" "scope → tier line"         'docs/trivial → haiku, normal → sonnet, risky/wide → opus, never fable'
check "$OBJ" "effort fallback"           '`low` docs/small, `medium` normal, `high` risky or wide'
check "$OBJ" "review-model alias list"   'haiku | sonnet | opus | fable | <model id>'

# --- start.md step 12b: issue-side signals and the mapping onto the same rows --
check "$STA" "12b heading"               '### 12b. Recommended model/effort profile (advisory)'
check "$STA" "risky path pattern"        "${pattern}"
check "$STA" "issue path threshold"      "more than ~${paths} repo paths"
check "$STA" "hardest → fable/high"      '`hardest` → `fable`/`high`'
check "$STA" "risky → opus/high"         '`risky / wide` → `opus`/`high`'
check "$STA" "normal → opus/medium"      '`normal` → `opus`/`medium`'
check "$STA" "docs → sonnet/low"         '`docs-only / trivial` → `sonnet`/`low`'
check "$STA" "auto tiers, never fable"   '(`opus` / `opus` / `sonnet` / `haiku`; never `fable`)'

echo "$pass in sync / $fail drifted / $((pass + fail)) total"
[ "$fail" -eq 0 ]
