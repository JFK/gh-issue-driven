#!/usr/bin/env bash
# tests/token-baseline-test.sh
#
# Self-test for tests/token-baseline.sh (issue #87, v0.14.0 milestone).
# Verifies the size-census TOOL behaves to contract — it does NOT assert the
# snapshot is in sync (the snapshot churns intentionally as commands/*.md are
# compressed in #89-#92). What it guards:
#   - the tool exists and is executable
#   - --check is informational (exits 0) and prints a per-file table + TOTAL
#   - ~tokens is the documented bytes/4 approximation
#   - --update is deterministic (idempotent), so snapshot diffs stay to the point
#   - right after --update, --check reports an exact match
#
# Run from anywhere: bash tests/token-baseline-test.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TOOL="$REPO_ROOT/tests/token-baseline.sh"
CMD_DIR="$REPO_ROOT/commands"
SNAPSHOT="$REPO_ROOT/tests/fixtures/token-baseline.txt"

fail() { echo "FAIL: $1"; exit 1; }

[ -x "$TOOL" ] || fail "tests/token-baseline.sh missing or not executable"

# --check must be informational: exit 0 even if the snapshot drifts.
OUT=$(bash "$TOOL" --check) || fail "--check exited non-zero (must be informational/exit 0)"

# Column header present.
printf '%s\n' "$OUT" | grep -q 'file' || fail "no column header line containing 'file'"

# One data row per command file, plus a TOTAL row. Use awk with a TAB field
# separator so we never embed literal tabs in this test.
NFILES=$(ls "$CMD_DIR"/*.md | wc -l | tr -d ' ')
NROWS=$(printf '%s\n' "$OUT" | awk -F'\t' 'NF==4 && $1 ~ /\.md$/ {c++} END{print c+0}')
[ "$NROWS" -eq "$NFILES" ] || fail "expected $NFILES file rows, got $NROWS"
printf '%s\n' "$OUT" | awk -F'\t' '$1=="TOTAL" && NF==4 {found=1} END{exit found?0:1}' \
  || fail "no TOTAL row with 4 tab-separated columns"

# ~tokens is bytes/4 (integer) for start.md.
B=$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="start.md"{print $3}')
T=$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="start.md"{print $4}')
[ -n "$B" ] || fail "no start.md row"
[ "$T" -eq "$((B / 4))" ] || fail "~tokens != bytes/4 for start.md (bytes=$B tokens=$T)"

# --update is deterministic.
bash "$TOOL" --update >/dev/null
H1=$(sha1sum "$SNAPSHOT" | cut -d' ' -f1)
bash "$TOOL" --update >/dev/null
H2=$(sha1sum "$SNAPSHOT" | cut -d' ' -f1)
[ "$H1" = "$H2" ] || fail "--update is not deterministic (snapshot hash changed between runs)"

# Right after --update, --check must report an exact match.
bash "$TOOL" --check | grep -q 'OK: matches snapshot' \
  || fail "--check should report 'OK: matches snapshot' immediately after --update"

echo "PASS: token-baseline.sh ($NFILES command files measured)"
