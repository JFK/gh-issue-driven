#!/usr/bin/env bash
# tests/token-baseline.sh
#
# Deterministic size census of commands/*.md (issue #87, v0.14.0 milestone).
# Measures per-command lines / bytes / approximate tokens, prints a table, and
# compares against the committed snapshot tests/fixtures/token-baseline.txt.
#
# WHY: before compressing the command prompt files (#89-#92) we need a
# deterministic baseline to prove the reduction and catch accidental bloat.
# Token count is a census, not a sample — no LLM/tokenizer needed.
#
# ~tokens is an APPROXIMATION (bytes / 4). There is no real tokenizer here; a
# byte census is enough to track the compression milestone's reductions.
#
# REPRODUCIBILITY: byte counts depend on line endings. This plugin is developed
# on Windows/WSL (CRLF risk) and CI runs on Linux (LF). Two defenses keep the
# numbers identical on both: (1) commands/*.md are pinned to LF via
# .gitattributes (text eol=lf); (2) this script strips CR before measuring, so
# a CRLF working-tree checkout still yields the same bytes as LF.
#
# MODES:
#   (default) / --check : measure, print the table, diff vs the snapshot, print
#                         any drift as a WARNING. ALWAYS exits 0 — informational
#                         only, never hard-fails on reduction or growth. (A
#                         bloat hard-fail guard is intentionally deferred to a
#                         follow-up after the compression milestone; see #87.)
#   --update            : (re)generate the snapshot file in place.
#
# Run from anywhere: bash tests/token-baseline.sh [--check|--update]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SNAPSHOT="$REPO_ROOT/tests/fixtures/token-baseline.txt"
CMD_DIR="$REPO_ROOT/commands"

MODE="check"
case "${1:-}" in
  --update)      MODE="update" ;;
  --check | "")  MODE="check" ;;
  *) echo "usage: token-baseline.sh [--check|--update]" >&2; exit 2 ;;
esac

# Emit the full snapshot text (header comments + sorted per-file rows + TOTAL).
# Deterministic: rows are sorted by filename; CR is stripped before counting.
generate() {
  local rows="" total_lines=0 total_bytes=0 total_tok=0
  local f name lines bytes tok
  for f in "$CMD_DIR"/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    lines=$(tr -d '\r' < "$f" | wc -l | tr -d ' ')
    bytes=$(tr -d '\r' < "$f" | wc -c | tr -d ' ')
    tok=$(( bytes / 4 ))
    total_lines=$(( total_lines + lines ))
    total_bytes=$(( total_bytes + bytes ))
    total_tok=$(( total_tok + tok ))
    rows+=$(printf '%s\t%s\t%s\t%s' "$name" "$lines" "$bytes" "$tok")$'\n'
  done
  printf '# token-baseline snapshot — commands/*.md size census (issue #87)\n'
  printf '# ~tokens is APPROXIMATE (bytes/4); byte counts assume LF (CR stripped, see .gitattributes)\n'
  printf '# columns: file<TAB>lines<TAB>bytes<TAB>~tokens   (regenerate: bash tests/token-baseline.sh --update)\n'
  printf '%s' "$rows" | sort
  printf 'TOTAL\t%s\t%s\t%s\n' "$total_lines" "$total_bytes" "$total_tok"
}

if [ "$MODE" = "update" ]; then
  mkdir -p "$(dirname "$SNAPSHOT")"
  generate > "$SNAPSHOT"
  echo "updated snapshot: tests/fixtures/token-baseline.txt"
  exit 0
fi

# --check mode: print the table, then diff against the snapshot (informational).
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
generate > "$TMP"
cat "$TMP"

if [ ! -f "$SNAPSHOT" ]; then
  echo "WARN: no snapshot yet — create it with: bash tests/token-baseline.sh --update" >&2
  exit 0
fi

if diff -u "$SNAPSHOT" "$TMP" >/dev/null 2>&1; then
  echo "OK: matches snapshot"
else
  echo "WARN: size drift vs snapshot (informational — not a failure):" >&2
  diff -u "$SNAPSHOT" "$TMP" >&2 || true
  echo "      if this drift is intended (e.g. a compression PR), refresh with: bash tests/token-baseline.sh --update" >&2
fi
exit 0
