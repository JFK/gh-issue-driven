# Fixture: typo-fix-issue

This file is a fixture for reproducible token measurement of the
gh-issue-driven plugin's token-efficiency flags (`auto-size`, `auto-skip`,
`--with-plan`, `--parallel`). See [CONTRIBUTING.md](../../CONTRIBUTING.md#measuring-token-consumption-rtk-gain)
for the measurement procedure.

The body below is what an operator would pass to `gh issue create --body-file
tests/fixtures/typo-fix-issue.md`, simulating a "small issue" that the
`gate1.size_heuristic` is designed to short-circuit. Use it for baseline-vs-PR
measurement of `auto-size` and (when paired with a docs-only diff) `auto-skip`.

The exact body length and label expectations are committed alongside the
markdown so a future change to the heuristic defaults can be reflected here
without losing reproducibility.

---

## Expected classification

- Body length: ~250 characters (well under the default `small_body_max_chars=500`).
- Suggested labels: `documentation` (matches default `small_labels`).
- Heuristic result (default config): **small** — `auto-size` should short-circuit gate1.

## Issue body (paste this into `gh issue create`)

```markdown
## Summary

The README "60-second quickstart" section says "60-seconds" with a hyphen in
one place and "60 seconds" without elsewhere. Pick one and use it consistently.

## Acceptance Criteria

- [ ] README.md uses one consistent spelling.
- [ ] README.ja.md uses the same convention.
```
