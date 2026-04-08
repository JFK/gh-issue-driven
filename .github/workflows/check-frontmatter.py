#!/usr/bin/env python3
"""Validate that every command file in commands/ has a parseable YAML
frontmatter block with a non-empty `description` field of at least 30 chars.

This is invoked by .github/workflows/lint.yml.
"""

from __future__ import annotations

import glob
import sys
from pathlib import Path

import yaml


def main() -> int:
    failures: list[str] = []
    files = sorted(glob.glob("commands/*.md"))
    if not files:
        print("ERROR: no command files found in commands/")
        return 1

    for path in files:
        text = Path(path).read_text(encoding="utf-8")
        parts = text.split("---", 2)
        if len(parts) < 3:
            failures.append(f"{path}: no YAML frontmatter (expected `---` ... `---`)")
            continue

        try:
            fm = yaml.safe_load(parts[1])
        except yaml.YAMLError as e:
            failures.append(f"{path}: frontmatter YAML parse error: {e}")
            continue

        if not isinstance(fm, dict):
            failures.append(f"{path}: frontmatter must be a YAML mapping")
            continue

        desc = fm.get("description", "")
        if not isinstance(desc, str) or not desc.strip():
            failures.append(f"{path}: missing or empty `description` field")
            continue

        if len(desc.strip()) < 30:
            failures.append(
                f"{path}: `description` is too short "
                f"(got {len(desc.strip())} chars, need >= 30)"
            )
            continue

        print(f"  OK  {path}")

    if failures:
        print()
        print(f"FAILED ({len(failures)}):")
        for f in failures:
            print(f"  {f}")
        return 1

    print(f"\nAll {len(files)} command files passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
