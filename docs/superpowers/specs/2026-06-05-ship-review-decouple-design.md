# Decouple post-PR review from `/ship`, make it opt-in, and compress `ship.md`

**Date:** 2026-06-05
**Status:** Approved — ready for implementation plan
**Scope:** `commands/ship.md`, `commands/review.md`, `commands/goal.md`, `commands/config.md`, `commands/doctor.md`, `commands/status.md`, `README.md`, `README.ja.md`, `CHANGELOG.md`, `tests/*`

## Problem

`ship.md` has grown to ~1102 lines / 77 KB. The largest single block — steps 13–14 (~400 lines) — is the post-PR review machinery (Copilot polling loop, GraphQL thread fetch/reply/resolve, the HITL invocation gate, autonomous bypass, draft promotion). This block is the **canonical source**; `review.md` is a terse wrapper that *references* `ship.md` ("Same as ship.md step 14.d", "per ship.md step 14.a rules", "See ship.md step 13c").

Two problems follow:

1. **Review fires by default.** `review.provider` effectively defaults to `copilot` (via legacy `copilot.enabled` back-compat), so every `/ship` auto-requests `@copilot` and drives a review loop. The operator wants review to be **opt-in** — run only when explicitly requested.
2. **`ship.md` is too large** to hold in context comfortably, and the review logic is duplicated in spirit across `ship.md` and `review.md`.

## Goals

- Flip `review.provider` default to `none`. `/ship` stops after PR creation unless review is explicitly requested.
- Invert the canonical source: `review.md` becomes the **self-contained home** of the post-PR review machinery; `ship.md` delegates to it.
- Reduce `ship.md` to ~660 lines (~40%).
- Add a `review.model` config (`auto|haiku|sonnet|opus`, default `auto`) that right-sizes the model used for applying review fixes, plus switch `goal.inner_review.model` default to `auto`.
- Keep `/goal` functionally unchanged — it consumes `/ship`'s `review.*` state, and the state contract is preserved.

## Non-goals

- `--review=skill:<name>` injection placeholder — explicitly **not** implemented (no doc placeholder, no reject-message change beyond what already exists).
- The gate2 advisor cascade (audit/cso/qa-lead/cto) and the `--review=code-reviewer` gate2 path — **untouched**. "review model" in this spec means the post-PR review fix work and goal's inner-review, never the gate2 reviewers.
- Merging PRs.

## Design

### 1. Default flip: `review.provider` → `none`

- In `ship.md` step ~2 (config load) and `review.md` step 3, the effective `review.provider` defaults to `none` when unset.
- **Remove the legacy `copilot.enabled` back-compat path** (currently: "if user config sets `copilot.enabled=false` → none, else copilot"). Going forward `copilot.enabled` is deprecated; document the migration to `review.provider` in `config.md`. A present-but-legacy `copilot.enabled` is ignored for provider determination (note in `doctor.md`).
- `NO_COPILOT` / `no-copilot` flag still forces `none` for a run (unchanged semantics, now redundant with the default but kept for `/goal` forwarding).

### 2. Canonical-source inversion: `review.md` owns the loop

Move the following from `ship.md` into `review.md`, in full detail (no longer referencing back to `ship.md`):

- The Copilot-specific **gh CLI version check** (ship.md lines ~85–117) — it only matters when the loop runs.
- **Step 13a** `/code-review` path, **13b** Copilot request, **13c** HITL invocation gate (incl. the DESIGN NOTES comment), **13c.d** declined-state writer.
- **Step 14.a–14.i**: polling, parse, exit conditions, address actionable comments, commit/push, thread reply+resolve, state write, draft promotion.
- The `JQ_DETECT_FILTER_BEGIN/END` canonical block becomes review.md's (see §5 for test sync).

`review.md` absorbs the detail it currently delegates; it grows from ~317 to ~600 lines and becomes self-contained. Cross-references flip direction: any remaining pointer goes review.md → (nothing); `ship.md`'s delegation step points to `/gh-issue-driven:review`.

### 3. `ship.md` becomes a thin delegator

Replace ship.md steps 13–14 with one delegation step after PR creation + gate2 state persist:

- If effective `REVIEW_PROVIDER == "none"` (the default): print the PR URL and a hint — `Review is opt-in. Run /gh-issue-driven:review to start the review loop.` — then continue to session-summary (step 15) and recap. No reviewer assigned, no loop.
- If `REVIEW_PROVIDER != "none"`: **invoke `/gh-issue-driven:review` via the Skill tool**, passing the PR number and forwarding `--autonomous=<level>` and `DRY_RUN`. `/review` runs the loop, writes the `review.*` state block, and returns. `ship.md` then proceeds to session-summary + recap, reading the loop outcome from state for the recap.

The only ways `REVIEW_PROVIDER` becomes non-`none` are: the effective config sets `review.provider`, or `/goal` forwards `--autonomous` (its config sets the provider). **No new ship flag is added** — a one-off review on a default-config repo is done by running `/gh-issue-driven:review` after ship, consistent with the opt-in philosophy.

Skill-invoking-skill is already an established pattern here (`ship` → `/code-review`, `/kagura-memory`; `goal` → `/start`, `/ship`).

### 4. Autonomous threading into `review.md`

`review.md` must accept and honor `--autonomous=<red-only|unattended|attended>` (currently only `ship.md` 13c implements the autonomous bypass):

- Parse `--autonomous` in review.md pre-flight.
- In the HITL invocation gate (moved from 13c), apply the **autonomous bypass**: when autonomous is active (red-only/unattended) and the gate would otherwise fire, auto-confirm (`hitl_decision="confirmed"`, `hitl_confirmed_at=now`) and run the loop unattended. `attended` = suppression-disabled (gate fires normally). This preserves the `/goal` → `/ship` → `/review` autonomy contract.

### 5. `review.model` config + `auto` right-sizing heuristic

New config key `review.model`, default `"auto"`. Accepted values: `auto`, `haiku`, `sonnet`, `opus`.

- **Fixed alias** → always dispatch the fix-application subagent at that tier.
- **`auto`** → right-size by the change being fixed:
  - docs-only / trivial (few lines) → `haiku`
  - normal feature change → `sonnet`
  - wide / risky (secret, auth, migration, broad diff) → `opus`
  - Reuse step 4a's `docs-only`/`mixed` diff-scope classification as the primary signal; add a small risk-keyword check for escalation.

**Behavioral change (called out for review):** today `review.md` applies review fixes inline on the session model. Under this design, the fix application is dispatched to a **subagent at the chosen tier** (Agent/Task with `model` override, same worktree). The subagent edits files and runs configured tests; the main loop commits/pushes/replies/resolves as before. This keeps the cheap-model intent while leaving commit/state orchestration on the main loop.

`goal.inner_review.model` default changes from `"haiku"` to `"auto"` (same heuristic; `review-model=<tier>` flag still overrides per run).

### 6. `/goal` impact (prose-only)

`/goal` step 5c still invokes `/ship --autonomous=<level>` and reads `review.copilot.exit_reason` from `/ship`'s state to decide `done` vs `needs_human`. Because `/ship` now delegates to `/review` which writes the **same `review.*` state block**, the contract is preserved. Updates needed:

- Reword step 5c / surrounding notes: "/ship drives the loop (steps 13–14)" → "/ship delegates the loop to `/gh-issue-driven:review`, which writes the same `review.*` state". No functional change to `/goal`.
- `goal.inner_review.model` default → `auto` (§5).
- Note: with `review.provider` default now `none`, `/goal`'s effective config must set `review.provider` (e.g. `copilot`) for the loop to run — document this in `config.md` and the `/goal` config notes.

## State / data contract

The `review.*` state block (schema_version 2) is **unchanged**. Both `/review` (canonical writer) and any reader (`/status`, `/goal`) use the same shape. `ship.md` no longer writes the `review.*` block itself except via delegation to `/review`. The gate2 state block written by `ship.md` is unchanged.

## Cross-reference / sync invariants to update

- `JQ_DETECT_FILTER_BEGIN/END` canonical block moves to `review.md`. `tests/jq-sync-check.sh` extracts the inline filter via sentinels — update its source path to `review.md`. `tests/copilot-detection.jq` / `.sh` and fixtures stay; verify equivalence target.
- `tests/test_state_schema.sh` — review-block invariants (incl. `hitl_declined` path) now exercised against `review.md`'s writer; confirm assertions still hold.
- `tests/enum-sync-check.sh` — exit_reason / provider enums; confirm no references to removed ship.md sections.
- `tests/review-threads.sh` — thread reply/resolve logic now in review.md; update any path reference.
- The `doctor.md` `PMRP_GLOB=claude-plugins-official/feature-dev*` sync with ship.md step 4b is **unaffected** (gate2 code-reviewer path stays in ship.md).

## Documentation

- `config.md`: document `review.provider` default `none`; new `review.model` key (default `auto`) with the heuristic; deprecate `copilot.enabled` with migration note.
- `doctor.md`: stop treating `copilot.enabled` as authoritative; note default-none and that review is opt-in.
- `status.md`: ensure recap copy reflects opt-in (a PR with no review is normal, not an anomaly).
- `README.md` / `README.ja.md`: update the ship/review flow description and the "Copilot fires automatically" wording.
- `CHANGELOG.md`: breaking-ish behavior change (review now opt-in) + new `review.model`.

## Testing strategy

- Existing `tests/*.sh` must pass after path/source updates (§ sync invariants).
- Manual/spec-level verification:
  - `/ship` with default config → PR created, no reviewer requested, hint printed, exit clean.
  - `/ship` with `review.provider=copilot` → delegates to `/review`, loop runs, state written.
  - `/review` standalone on an open PR → unchanged behavior (now canonical).
  - `/goal` end-to-end with `review.provider=copilot` in config → loop runs via delegation, `done`/`needs_human` mapping intact.
  - `review.model=auto` → docs-only diff picks haiku; risky diff escalates.

## Risks & mitigations

- **Subagent fix-application regresses quality** (haiku too weak): `auto` escalates risky changes to sonnet/opus; tests run inside the subagent before commit; gate2 already passed pre-PR.
- **Broken cross-references** after the move: the sync-check tests are the guardrail; enumerate every `ship.md step 1Xx` reference in `review.md`/`goal.md` and repoint.
- **`/goal` silently stops reviewing** because default is now none: documented requirement that goal's config sets `review.provider`; `/goal` recap already surfaces `copilot=<exit>` / `needs_human`, making a no-review run visible.

## Open questions

None — all design decisions confirmed during brainstorming.
