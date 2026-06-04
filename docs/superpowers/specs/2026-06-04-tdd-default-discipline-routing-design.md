# TDD as a default implementation discipline in `/start` and `/goal`

**Date:** 2026-06-04
**Status:** Approved design — ready for implementation plan
**Scope:** `commands/start.md` (steps 17b/17c/18), `commands/goal.md` (step 5b wording + cross-reference), docs (README sync)

## Problem

`superpowers:test-driven-development` is a **discipline skill** (an inner red→green→refactor loop applied while writing code), not an orchestration skill like `feature-dev:feature-dev`, `superpowers:writing-plans`, or `superpowers:subagent-driven-development`. Today the two are conflated in `/start`:

- **Step 17c** prints TDD as if it were a fourth selectable tier (`(横断的) test-first where it fits ← only if detected`), alongside the orchestration tiers (Trivial / Moderate / Large).
- **Step 18** never actually routes to TDD. Its continue-target precedence (18b) resolves only to `feature-dev` (when detected) or a plan/conversational draft. The `Large → subagent` tier auto-launches **only** under `--parallel`; the `test-first → TDD` tier **never** auto-launches.

Result: a menu that advertises four tiers but wires roughly two, and TDD — the one discipline the TDD skill says applies *always* — has no real place. Meanwhile `/goal` step 5b already treats TDD correctly ("TDD as an invariant, not a forced march"), so `/start` and `/goal` are asymmetric.

## Goal

Formalize a **two-layer model** and make it consistent across `/start` and `/goal`:

- **Orchestration layer** (chosen by size/risk): direct edits / `feature-dev` / `writing-plans → subagent-driven-development`.
- **Discipline layer** (default-on): `superpowers:test-driven-development` runs *inside* the implementation of whichever orchestration is chosen, wherever the change has a test surface.

Concretely: TDD becomes the **default implementation discipline**, not a selectable route. The only "choice" is orchestration; TDD is on by default where there is real logic to assert, and opted out only for pure docs / rename / config.

### Non-goals (YAGNI)

- No TDD on/off toggle UI (a toggle invites the "skip just this once" rationalization the TDD skill explicitly warns against).
- TDD is **not** promoted to a standalone mutually-exclusive route.
- The Q2 "green stops under `/goal`" harness-hardening (autonomous-flag threading) is a **separate issue**, out of scope here.

## Design

### Two-layer model (the invariant being encoded)

```
Orchestration (pick by size/risk)             Discipline (default during implementation)
─────────────────────────────────            ──────────────────────────────────────────
Trivial  (docs / rename / config) → direct    (no test surface → no TDD)
Moderate                          → feature-dev   ┐
Large / plan-driven               → writing-plans ├─→ implement test-first via
                                    → subagent     ┘    superpowers:test-driven-development
```

The TDD opt-out condition is one **canonical string** used verbatim in `/start` 17b/17c/18e and `/goal` 5b: skip the cycle only when there is genuinely nothing to assert — **"pure docs / formatting / rename / config"**. Never manufacture a token test to satisfy the ritual.

### Change 1 — `/start` step 17b/17c (Suggested workflow display)

- **17b (detection):** keep detecting the orchestration skills and `/code-review` as today. Detect `superpowers:test-driven-development` separately — it is the discipline, not a tier.
- **17c (printed workflow):** present the orchestration tiers as *the choice* (Trivial→direct / Moderate→feature-dev / Large→writing-plans→subagent), each shown only when its skill is detected (the "direct edits" tier is always shown). Then state TDD **once**, as the default discipline that applies to whichever tier touches real logic — not as a tier bullet. The test-first **discipline sub-line is always shown** because the default applies with or without the skill; only the skill *name* (`superpowers:test-driven-development`) is detection-gated — when undetected, the line drops the name and reads "drive it test-first manually". Use the canonical opt-out string so `/start` 17c and `/goal` 5b read identically.
- The "omit silently when not installed" rule (existing 17b behavior) still applies to every **orchestration/review** skill named. The test-first discipline is the **one carve-out**: its sub-line is always shown (it is a discipline, not a launchable tier), and only the skill name is gated. (This refines the original AC's "TDD line is detection-gated": per gate1's DX-Lead suggestion, the test-first *default* must hold even when the skill is absent — otherwise a machine without superpowers silently loses the discipline. Only the skill *name* is gated, not the discipline line.)

### Change 2 — `/start` step 18 (continue-target action)

- **18b (pick continue target):** unchanged in *which orchestration* it resolves to (parallel→subagent / batch→plan / feature-dev→feature-dev / else→draft). TDD is **not** added as a new continue target.
- **18e (perform the action):** the action that actually implements — launching `feature-dev`, drafting-and-implementing a plan, or direct conversational implementation — is instructed to proceed **test-first via `superpowers:test-driven-development` when the change has a test surface** (same opt-out as 17c/5b). TDD is wired as a *property of the continue action*, not a menu item.
- **Honesty fix (17c ↔ 18 mismatch):** reconcile what 17c advertises with what 18 can launch. Specifically, the `Large → subagent` tier is only auto-launched under `--parallel`; without `--parallel` the continue target falls to a plan draft. 17c's text must not imply step 18 will auto-launch a tier it cannot. Either (a) annotate the `Large` tier in 17c to note it auto-launches only with `--parallel` (otherwise step 18 drafts a plan the operator runs), or (b) equivalent wording — chosen during implementation, but the printed menu and the actual 18b behavior must agree.

### Change 3 — `/goal` step 5b (already implemented; align + cross-reference)

- 5b already drives TDD as an invariant. No behavior change. **Align the wording** with `/start` 17c so the opt-out condition is phrased identically, and add a one-line note that TDD is the default discipline in **both** `/start` and `/goal` (cross-reference), so a reader of either command sees the same contract.

### Change 4 — docs

- Sync `README.md` / `README.ja.md` where they describe the `/start` implementation-guidance / suggested-workflow step, so the documented behavior matches: orchestration is chosen by size; TDD is the default discipline.

## Affected files

| File | Change |
|---|---|
| `commands/start.md` | 17b detect TDD as discipline; 17c reframe tiers + TDD-as-default line; 18e make continue action test-first; reconcile 17c↔18 mismatch |
| `commands/goal.md` | 5b wording alignment + cross-reference note (no behavior change) |
| `README.md`, `README.ja.md` | sync the `/start` workflow description |
| `CHANGELOG.md` | entry under the next release |

## Testing / verification

This repo's "tests" are documentation-consistency checks (markdown command files, no runtime). Verification:

- `/gh-issue-driven:doctor` still passes (no schema/flag changes introduced).
- Manual dogf-read: confirm 17c's printed tiers and 18b's actual continue-target resolution agree (no tier advertised that 18 cannot launch).
- Confirm `/start` 17c and `/goal` 5b state the same TDD opt-out condition (string-level consistency).
- Confirm the test-first sub-line in 17c is **always shown**, with only the skill *name* detection-gated (the line reads "drive it test-first manually" when `superpowers:test-driven-development` is not installed).
- No config schema change → no `config.md` default additions required.

## Risks

- **Over-application of TDD** to changes with no real test surface. Mitigated by carrying `/goal` 5b's exact opt-out wording ("nothing to assert → skip; do not manufacture a token test").
- **Wording drift** between `/start` and `/goal`. Mitigated by making 5b the canonical source and cross-referencing rather than duplicating divergent prose.
