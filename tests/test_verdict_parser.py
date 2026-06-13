#!/usr/bin/env python3
"""
tests/test_verdict_parser.py

Reference implementation of the gh-issue-driven verdict parser contract.
Runs against markdown fixtures in tests/fixtures/verdicts/ and validates
each fixture's parsed verdict against tests/fixtures/verdicts/expected.json.

Three parser modes:
  - advisory: gate2 advisors (and gate1's green/yellow/red path) → green | yellow | red
  - binary:   gate2 binary gate                                  → pass | fail
  - gate1:    gate1 decline-detection (start.md step 10)         → green | yellow | red | decline
              (`decline` is structured-only — never a heuristic result)

Both modes share the same two-step contract:
  1. Structured verdict line (last wins): ^\\s*##\\s*Verdict:\\s*<token>\\b
  2. Heuristic fallback (only when no structured line found)

Run from repo root: python3 tests/test_verdict_parser.py
"""

import json
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES_DIR = SCRIPT_DIR / "fixtures" / "verdicts"
EXPECTED_FILE = FIXTURES_DIR / "expected.json"

# --- Structured verdict patterns (step 1 of the contract) ---

ADVISORY_PATTERN = re.compile(
    r"^\s*##\s*Verdict:\s*(green|yellow|red)\b", re.IGNORECASE | re.MULTILINE
)

BINARY_PATTERN = re.compile(
    r"^\s*##\s*Verdict:\s*(pass|fail)\b", re.IGNORECASE | re.MULTILINE
)

# gate1 emits the advisory tokens PLUS `decline` (the /ceo-escalation signal).
# This MUST match start.md step 10's expanded scan
# `^\s*##\s*Verdict:\s*(green|yellow|red|decline)\b`.
GATE1_PATTERN = re.compile(
    r"^\s*##\s*Verdict:\s*(green|yellow|red|decline)\b", re.IGNORECASE | re.MULTILINE
)

# --- Heuristic tokens (step 2 of the contract) ---

# Advisory red tokens (case-insensitive substring match)
ADVISORY_RED_TOKENS = ["BLOCKER", "must fix before", "red flag", "do not proceed"]

# Advisory yellow tokens (case-insensitive substring match)
ADVISORY_YELLOW_TOKENS = ["WARN", "consider", "recommend"]

# Binary fail tokens (case-insensitive substring match)
BINARY_FAIL_TOKENS = ["BLOCKER", "failed conformance", "MUST FIX"]


def count_pattern(text: str, pattern: str) -> int:
    """Count occurrences of a case-insensitive pattern in text."""
    return len(re.findall(re.escape(pattern), text, re.IGNORECASE))


def parse_advisory(text: str) -> str:
    """Parse advisory verdict: green | yellow | red.

    Used by gate1 (start.md step 11) and gate2 advisors (ship.md step 8).
    """
    # Step 1: structured verdict line — last wins
    matches = ADVISORY_PATTERN.findall(text)
    if matches:
        return matches[-1].lower()

    # Step 2: heuristic fallback
    text_lower = text.lower()

    # Red heuristics
    for token in ADVISORY_RED_TOKENS:
        if token.lower() in text_lower:
            return "red"
    if count_pattern(text, "Critical:") >= 3:
        return "red"

    # Yellow heuristics
    for token in ADVISORY_YELLOW_TOKENS:
        if token.lower() in text_lower:
            return "yellow"
    warning_count = count_pattern(text, "Warning:")
    if 1 <= warning_count <= 2:
        return "yellow"

    # Default
    return "green"


def parse_gate1(text: str) -> str:
    """Parse gate1 verdict: green | yellow | red | decline.

    Used by gate1 (start.md step 10's decline-detection scan). `decline` is the
    /ceo-escalation signal and is ONLY ever a structured-line token — a free-form
    mention of "decline" in the reasoning body must NOT trigger it. So the
    heuristic fallback (no structured line) reuses the advisory classifier, which
    can never return `decline`.
    """
    # Step 1: structured verdict line — last wins (includes decline)
    matches = GATE1_PATTERN.findall(text)
    if matches:
        return matches[-1].lower()

    # Step 2: no structured line — decline is never heuristic; defer to advisory.
    return parse_advisory(text)


def parse_binary(text: str) -> str:
    """Parse binary gate verdict: pass | fail.

    Used by gate2 binary gate (ship.md step 7).
    """
    # Step 1: structured verdict line — last wins
    matches = BINARY_PATTERN.findall(text)
    if matches:
        return matches[-1].lower()

    # Step 2: heuristic fallback
    text_lower = text.lower()
    for token in BINARY_FAIL_TOKENS:
        if token.lower() in text_lower:
            return "fail"

    # Default
    return "pass"


def main() -> int:
    if not EXPECTED_FILE.exists():
        print(f"FAIL: expected.json not found: {EXPECTED_FILE}")
        return 1

    with open(EXPECTED_FILE) as f:
        expected_map = json.load(f)

    if not expected_map:
        print("FAIL: expected.json is empty")
        return 1

    passed = 0
    failed = 0
    total = 0

    for filename, spec in sorted(expected_map.items()):
        total += 1
        fixture_path = FIXTURES_DIR / filename
        mode = spec["mode"]
        expected = spec["expected"]

        if not fixture_path.exists():
            print(f"FAIL {filename}: fixture file not found")
            failed += 1
            continue

        text = fixture_path.read_text(encoding="utf-8")

        if mode == "advisory":
            actual = parse_advisory(text)
        elif mode == "binary":
            actual = parse_binary(text)
        elif mode == "gate1":
            actual = parse_gate1(text)
        else:
            print(f"FAIL {filename}: unknown mode '{mode}'")
            failed += 1
            continue

        if actual == expected:
            print(f"PASS {filename:<55s} mode={mode:<8s} expected={expected:<6s} got={actual}")
            passed += 1
        else:
            print(f"FAIL {filename:<55s} mode={mode:<8s} expected={expected:<6s} got={actual}")
            failed += 1

    print("---")
    print(f"{passed} passed / {failed} failed / {total} total")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
