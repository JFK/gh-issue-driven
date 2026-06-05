# Decouple post-PR review from /ship — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `review.md` the self-contained canonical home of the post-PR review loop, turn review into an opt-in (`review.provider` default `none`), reduce `ship.md` ~40%, and add a `review.model` (default `auto`) that right-sizes the fix-application model.

**Architecture:** Invert the ship↔review reference direction. `review.md` absorbs the full Copilot loop + HITL + autonomous bypass + draft promotion (today it references `ship.md`). `ship.md` becomes a thin delegator: default `none` → stop after PR; provider set or `--autonomous` → invoke `/gh-issue-driven:review`. `/goal` is functionally unchanged (reads the same `review.*` state). The JQ_DETECT_FILTER canonical block (already duplicated in both files) moves its sync anchor to `review.md`.

**Tech Stack:** Markdown command files (`commands/*.md`), bash test harness (`tests/*.sh`, `tests/*.py`), `gh` CLI, jq.

**Spec:** `docs/superpowers/specs/2026-06-05-ship-review-decouple-design.md`
**Issue:** #83

**Verification model (no unit-test framework — this is prose+config refactoring):**
- The existing `tests/*.sh` / `tests/*.py` suite is the regression harness.
- Per-task verification uses: targeted `grep` structural assertions, `bash tests/<name>.sh`, and `wc -l` line-count gates.
- Run the whole suite with the loop below; every task that touches `commands/` or `tests/` must end with it green:

```bash
# FULL SUITE — used by multiple tasks
cd /home/jfk/works/gh-issue-driven
for t in tests/jq-sync-check.sh tests/enum-sync-check.sh tests/copilot-detection.sh tests/review-threads.sh tests/test_state_schema.sh; do
  echo "== $t =="; bash "$t" || { echo "FAIL: $t"; exit 1; }
done
python3 tests/test_verdict_parser.py && echo "ALL TESTS PASS"
```

> Commit after every task. Branch off `main` first (see Task 0).

---

### Task 0: Branch and baseline

**Files:** none (git only)

- [ ] **Step 1: Create the working branch**

```bash
cd /home/jfk/works/gh-issue-driven
git checkout -b feat/83-decouple-ship-review main
```

- [ ] **Step 2: Capture the baseline — tests green + line counts**

```bash
for t in tests/jq-sync-check.sh tests/enum-sync-check.sh tests/copilot-detection.sh tests/review-threads.sh tests/test_state_schema.sh; do bash "$t" || echo "PRE-FAIL: $t"; done
python3 tests/test_verdict_parser.py
wc -l commands/ship.md commands/review.md
```

Expected: all tests pass; `ship.md` ≈ 1102 lines, `review.md` ≈ 317 lines. Record these numbers — Task 5 asserts `ship.md` dropped to ~660.

- [ ] **Step 3: Commit the plan + spec onto the branch** (spec already committed on `main` as `bd509fa`; nothing to commit here if branch was cut from that commit). Skip if clean.

---

### Task 1: Make `review.md` the self-contained canonical loop

Today `review.md` step 5 references `ship.md` ("Same as ship.md step 14.d", "per ship.md step 14.a rules", "See ship.md step 13c"). Inline that detail so `review.md` stands alone. The Copilot loop body, GraphQL thread fetch/reply/resolve, the HITL invocation gate (incl. its DESIGN NOTES), the declined-state writer, and the draft-promotion logic must all live in `review.md` with no back-reference to `ship.md`.

**Files:**
- Modify: `commands/review.md` (steps 5–5c, and add the moved detail)
- Read for source-of-truth copy: `commands/ship.md:85-117` (gh version check), `commands/ship.md:689-781` (13c/13c.d HITL), `commands/ship.md:855-962` (14.d/14.f thread+reply+resolve detail)

- [ ] **Step 1: Write the verification assertion first (it should FAIL now)**

```bash
# review.md must NOT reference ship.md for the loop internals after this task
grep -nE "ship\.md step (13c|14\.[a-i])|per ship\.md|Same as ship\.md|See \`?ship\.md" commands/review.md
```
Expected NOW: several matches (≈6). Goal after the task: **zero** matches.

- [ ] **Step 2: Inline the HITL invocation gate into `review.md` step 5a**

In `commands/review.md`, replace the delegation paragraph (currently `Before entering the polling loop below, apply the **HITL confirmation gate** as defined in ship.md step 13c. …` through `See ship.md step 13c for the DESIGN NOTES …`) with the full gate text copied from `commands/ship.md` step 13c (lines ~689–745) and 13c.d (lines ~746–781). Keep the DESIGN NOTES HTML comment. Adapt step-number cross-refs to review.md's own numbering (13c→5a, 14→5b, 14.g→6). Preserve all state-write invariants verbatim.

- [ ] **Step 3: Inline the thread-fetch / reply / resolve detail into `review.md` step 5b**

Replace the terse `Address actionable comments: Same as ship.md step 14.d …` and `Reply to threads and resolve: Same as ship.md step 14.f …` lines with the full bodies copied from `commands/ship.md` 14.d (the GraphQL `reviewThreads` query, lines ~855–905) and 14.f (per-thread reply/resolve bash, lines ~920–962). Keep `THREADS_REPLIED`/`THREADS_RESOLVED` tracking.

- [ ] **Step 4: Inline the gh CLI version check into `review.md` step 5 preamble**

Copy the warn-only gh-version block from `commands/ship.md:85-117` to the top of `review.md` step 5 (before 5a), since it only matters when the loop runs. Keep it warn-only.

- [ ] **Step 5: De-reference remaining pointers**

Replace every remaining `per ship.md step 14.a rules` / `per ship.md step 14.b` with the actual one-line rule inlined (detection-state update rules; REVIEW_DECISION/NEW_COMMENTS parse). Source: `commands/ship.md:818-854`.

- [ ] **Step 6: Run the assertion — expect PASS now**

```bash
grep -cE "ship\.md step (13c|14\.[a-i])|per ship\.md|Same as ship\.md|See \`?ship\.md" commands/review.md
```
Expected: `0`.

- [ ] **Step 7: Sanity — review.md still has the JQ_DETECT_FILTER block and parses sentinels uniquely**

```bash
grep -c "JQ_DETECT_FILTER_BEGIN\|JQ_DETECT_FILTER_END" commands/review.md   # expect 2
```

- [ ] **Step 8: Commit**

```bash
git add commands/review.md
git commit -m "refactor(review): inline post-PR loop detail — review.md is now self-contained"
```

---

### Task 2: Add `review.model` + `auto` right-sizing to `review.md`

**Files:**
- Modify: `commands/review.md` (step 2/3 config load; step 5b fix-application)

- [ ] **Step 1: Add `review.model` to review.md config load**

In `commands/review.md` step 3 (provider determination) add, right after the provider line:

```markdown
Read `REVIEW_MODEL` from `review.model` in the effective config (default `"auto"`). Valid values: `auto`, `haiku`, `sonnet`, `opus`, or a full model id. `REVIEW_MODEL` governs only the **fix-application subagent** in step 5b — never the provider selection, never `/code-review`'s own effort.
```

- [ ] **Step 2: Add the `auto` right-sizing rule + subagent dispatch to step 5b**

In `review.md` step 5b, where actionable comments are addressed, replace the inline "apply changes via Edit/Bash" instruction with a subagent dispatch:

```markdown
**Resolve `REVIEW_MODEL` to a concrete tier.** If `REVIEW_MODEL == "auto"`, right-size from the change under review:
- compute the changed-file set for this PR (`gh pr diff "$PR_NUMBER" --name-only`);
- **docs-only / trivial** (all paths match `*.md`/`docs/`, or < ~20 changed lines) → `haiku`;
- **risky / wide** (any path matching `auth|secret|credential|migration|security`, or > ~10 files / > ~400 changed lines) → `opus`;
- **otherwise** → `sonnet`.
A fixed alias (`haiku|sonnet|opus|<id>`) is used verbatim.

**Dispatch the fix-application subagent** at the resolved tier via the Agent tool (`model: <tier>`), passing: the sanitized actionable thread bodies, the issue acceptance criteria, and the repo conventions. The subagent edits files in the working tree and runs `copilot.run_tests_after_edits` tests if configured, then returns a one-line-per-fix summary. The main loop (not the subagent) performs the commit/push (5b) and thread reply/resolve (5b). Log `review: fix-application on <tier> tier (review.model=<config value>)`.
```

- [ ] **Step 3: Verify the new keys are documented inline and sentinels intact**

```bash
grep -n "review.model\|REVIEW_MODEL\|right-size" commands/review.md   # expect several
bash tests/review-threads.sh   # thread logic still parses
```
Expected: matches present; test passes.

- [ ] **Step 4: Commit**

```bash
git add commands/review.md
git commit -m "feat(review): add review.model with auto right-sizing for fix-application"
```

---

### Task 3: Add `--autonomous` handling to `review.md`

`review.md` is invoked standalone today (no autonomy). When `ship.md` delegates (Task 5) it forwards `--autonomous`. The bypass logic that lived in ship 13c is now in review.md (Task 1) — wire the flag to it.

**Files:**
- Modify: `commands/review.md` (step 1 pre-flight arg parse; step 5a gate)

- [ ] **Step 1: Parse `--autonomous[=<level>]` in review.md step 1**

Add to `commands/review.md` step 1 (after branch validation):

```markdown
Parse `--autonomous[=<level>]` from `$ARGUMENTS` (default unset → `AUTONOMOUS_LEVEL=null`, `AUTONOMOUS=false`). Bare `--autonomous` means `red-only`. Validate against `^(red-only|unattended|attended)$` and reject otherwise. Derive `AUTONOMOUS = (level is red-only or unattended)`; `attended` disables suppression (`AUTONOMOUS=false`), identical to absent. Also parse a PR number argument (`#<n>` or `<n>`) when present — when invoked by `/ship` it is passed explicitly; standalone it is read from state as today.
```

- [ ] **Step 2: Wire the autonomous bypass into the step 5a HITL gate**

In the HITL gate inlined in Task 1, add the autonomous-bypass branch (copied from ship 13c's "Autonomous bypass" paragraph): when `AUTONOMOUS` is true and the gate would otherwise fire, auto-confirm (`hitl_decision="confirmed"`, `hitl_confirmed_at=<now>`) and run the loop unattended; log `autonomous(<level>): Copilot-invocation HITL auto-confirmed`.

- [ ] **Step 3: Verify**

```bash
grep -n "AUTONOMOUS\|--autonomous\|auto-confirmed" commands/review.md   # expect matches
bash tests/test_state_schema.sh   # hitl_declined/confirmed state invariants still hold
```

- [ ] **Step 4: Commit**

```bash
git add commands/review.md
git commit -m "feat(review): honor --autonomous (bypass moved from ship 13c)"
```

---

### Task 4: Repoint all review-loop test anchors from `ship.md` to `review.md`

Three test files key off `ship.md`'s review sections, which Task 5 removes. Repoint them now — `review.md` already holds the canonical content (JQ block, schema template, exit-condition + stay-as-draft lists), so every check stays green before and after Task 5. `test_verdict_parser.py` references `ship.md` only for **gate2** (steps 7–8), which stays — leave it untouched.

**Files:**
- Modify: `tests/jq-sync-check.sh` (source path + comments), `tests/enum-sync-check.sh` (file arrays + comments), `tests/review-threads.sh` (comments only)

- [ ] **Step 1: jq-sync-check.sh — repoint the source file**

Replace `SHIP_MD="$REPO_ROOT/commands/ship.md"` (line 32) with `REVIEW_MD="$REPO_ROOT/commands/review.md"` and update every later `$SHIP_MD` usage to `$REVIEW_MD`. Update the prose comments (lines 4, 17–18, 118) that say "ship.md step 13" / "in ship.md" / "ship.md inline jq has drifted" to reference `review.md` step 5b.

```bash
bash tests/jq-sync-check.sh && echo "jq-sync OK"
```
Expected: PASS (now reading review.md's inline filter).

- [ ] **Step 2: enum-sync-check.sh — drop ship.md from the review-schema arrays, add review.md where it now parses the flag**

In `tests/enum-sync-check.sh`:
- The schema-template / exit-conditions / stay-as-draft file array (around lines 65–66) currently lists **both** `ship.md` and `review.md`. After Task 5, ship.md no longer carries those — **remove the `"$REPO_ROOT/commands/ship.md"` entry from that array**, keep `review.md`.
- The autonomy/`hitl_decision` array (around line 75) lists `start.md` + `ship.md`. `review.md` now parses `--autonomous` and writes `hitl_decision` (Task 3) — **add `"$REPO_ROOT/commands/review.md"`** to that array. `ship.md` still forwards `--autonomous`, so keep it.
- Update the explanatory comments (lines 11–14, 70–71, 117, 119) to say the review schema/exit-conditions/`hitl_decision` now live in `review.md` (consumed-by note: ship.md forwards the flag, review.md owns the loop state).

```bash
bash tests/enum-sync-check.sh && echo "enum-sync OK"
```
Expected: PASS (review.md holds the canonical enums; ship.md still has them too at this point, but is no longer required to).

- [ ] **Step 3: review-threads.sh — comment-only repoint**

The mirror filter is embedded in the test (it does not read `ship.md`). Update the comments (lines 5, 9–10, 30) from "ship.md step 14.d" / "ship.md / review.md" to "review.md step 5b" (drop the ship.md mention, since the inline filter no longer lives there).

```bash
bash tests/review-threads.sh && echo "threads OK"
```
Expected: PASS (unchanged behavior).

- [ ] **Step 4: Full suite**

Run the FULL SUITE block. Expected: ALL TESTS PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/jq-sync-check.sh tests/enum-sync-check.sh tests/review-threads.sh
git commit -m "test: repoint review-loop sync anchors from ship.md to review.md"
```

---

### Task 5: Slim `ship.md` — default none, delegate, drop the loop

**Files:**
- Modify: `commands/ship.md` — frontmatter description (line 2), step 2 provider determination (line ~137), gh-version check (lines ~85–117), steps 13–14 (lines ~623–1028), Trust boundary (line ~31), recap (step 16), Failure modes, the bottom warning.

- [ ] **Step 1: Flip the provider default + drop legacy `copilot.enabled`**

Edit `commands/ship.md` line ~137. Replace:

> Determine `REVIEW_PROVIDER` as follows: if the **user config** explicitly sets `review.provider`, use that value. Otherwise, for backward compatibility with v0.1.x configs, check legacy `copilot.enabled`: if the user config explicitly sets `copilot.enabled` to `false`, set `REVIEW_PROVIDER="none"`; otherwise default to `"copilot"`. Valid values: `copilot`, `code-review`, `both`, `none`. If `NO_COPILOT` is set, override `REVIEW_PROVIDER` to `"none"` for this invocation (backward compatibility).

with:

> Determine `REVIEW_PROVIDER`: if the **user config** sets `review.provider`, use it; otherwise default to `"none"` (review is opt-in). Valid values: `copilot`, `code-review`, `both`, `none`. The legacy `copilot.enabled` field is **no longer consulted** (deprecated — see `/gh-issue-driven:config`). If `NO_COPILOT` is set, `REVIEW_PROVIDER="none"` for this invocation.

- [ ] **Step 2: Replace steps 13–14 with a thin delegation step**

Delete `commands/ship.md` from the `### 13. Post-PR review — provider dispatch` heading through the end of `#### 14.i.` (lines ~623–1028). Replace with:

```markdown
### 13. Post-PR review (delegated)

**If `REVIEW_PROVIDER == "none"`** (the default): print the PR URL and
`Review is opt-in. Run /gh-issue-driven:review to start the review loop.`
Then continue to step 14 (session summary). No reviewer is requested; no loop runs.

**If `REVIEW_PROVIDER != "none"`** (config set, or `/goal` forwarded `--autonomous`):
> **Invoke `/gh-issue-driven:review` via the Skill tool**, passing the PR number and forwarding `--autonomous=<level>` (when set) and `dry-run` (when `DRY_RUN`). `/review` runs the loop, writes the `review.*` state block, and returns.

Read the loop outcome (`review.copilot.exit_reason`, `review.provider`, counts) back from the state file for the step-15 recap. `/ship` does **not** write the `review.*` block itself — `/review` owns it. The PR is never created on the default branch and never force-pushed (unchanged).
```

(Renumber the trailing steps if needed, or keep "14. Save the session summary" / "16. recap" labels and adjust the cross-references in this new step accordingly. Match whatever numbering already follows.)

- [ ] **Step 3: Remove the Copilot-specific gh-version check**

Delete the `#### gh CLI version check (warn-only, runs unconditionally)` block at `commands/ship.md:85-117` (now lives in `review.md`, Task 1 step 4). Keep the rest of pre-flight.

- [ ] **Step 4: Update Trust boundary, recap, Failure modes, and the bottom warning**

- Trust boundary (line ~31): drop the "Copilot review comments" clause (that handling moved to review.md); keep reviewer-skill-output-as-data.
- Frontmatter `description` (line 2): change "creates the PR, drives a Copilot review loop up to 5 iterations, and saves session knowledge" → "creates the PR (review is opt-in via /gh-issue-driven:review), and saves session knowledge".
- Recap (step ~16): when provider is none, show `Review   opt-in — run /gh-issue-driven:review`. When delegated, show the outcome read from state.
- Failure modes table: remove rows specific to the in-ship Copilot loop (silent_no_op etc. now belong to review.md); keep gate2/PR rows.
- Bottom `⚠️ AI-orchestrated` warning: drop "drives a Copilot review loop that may commit and push code" (delegated now).

- [ ] **Step 5: Verify structure + line-count gate**

```bash
grep -n "copilot.enabled" commands/ship.md            # expect 0 matches
grep -n "JQ_DETECT_FILTER" commands/ship.md           # expect 0 (moved to review.md)
grep -n "Run /gh-issue-driven:review" commands/ship.md # expect the delegation hint
wc -l commands/ship.md                                 # expect ~660 (was ~1102)
```
Expected: `copilot.enabled` and `JQ_DETECT_FILTER` gone from ship.md; delegation hint present; line count dropped ~40%.

- [ ] **Step 6: Full suite (jq-sync now reads review.md, so still green)**

Run the FULL SUITE block. Expected: ALL TESTS PASS.

- [ ] **Step 7: Commit**

```bash
git add commands/ship.md
git commit -m "refactor(ship): delegate post-PR review to /review, default none, ~40% smaller"
```

---

### Task 6: Update `config.md`

**Files:**
- Modify: `commands/config.md` — `review.provider` section (line ~49–62), `inner_review.model` (line ~163), JSON example (lines ~265, ~310), add `review.model` row.

- [ ] **Step 1: Change `review.provider` default + deprecate `copilot.enabled`**

In `commands/config.md` `### review.provider` (line ~49), change the documented default from `copilot` to `none`. Replace the "Interaction with copilot.enabled" paragraph (line 60) with:

```markdown
**Deprecated: `copilot.enabled`** — no longer consulted. Previously, when `review.provider` was absent, a `copilot.enabled=false` forced `none`. As of this version the default is `none` regardless, and `copilot.enabled` is ignored. Migrate by setting `review.provider` explicitly (`"copilot"` to restore the old auto-review behavior).
```

- [ ] **Step 2: Add the `review.model` key row**

Add near the `review.provider` doc (and to the JSON example block at line ~265):

```markdown
### `review.model`
Default `"auto"`. One of `auto | haiku | sonnet | opus` (or a full model id). Tier for the **fix-application subagent** that `/gh-issue-driven:review` dispatches to apply review findings. `auto` right-sizes by the PR's diff scope/risk (docs-only → haiku, normal → sonnet, risky/wide → opus). Does not affect provider selection, the gate2 cascade, or `/code-review`.
```

JSON example: under the `"review"` block add `"model": "auto"` alongside `"provider": "none"` (change `"copilot"` → `"none"` at line ~265).

- [ ] **Step 3: Change `inner_review.model` default to `auto`**

In `commands/config.md` line ~163, change `| `inner_review.model` | `"haiku"` |` → `| `inner_review.model` | `"auto"` |` and update the description: "Model tier for the inner-review subagent. `auto` right-sizes by working-tree diff scope (docs→haiku, normal→sonnet, risky→opus); a fixed alias is used verbatim." Update the JSON example at line ~310: `"model": "haiku"` → `"model": "auto"`.

- [ ] **Step 4: Verify**

```bash
grep -n '"provider": "none"\|"model": "auto"\|review.model\|Deprecated: `copilot.enabled`' commands/config.md
```
Expected: all present.

- [ ] **Step 5: Commit**

```bash
git add commands/config.md
git commit -m "docs(config): review.provider default none, add review.model, inner_review.model auto, deprecate copilot.enabled"
```

---

### Task 7: Update `goal.md`

`/goal` stays functional (reads `review.*` state). Only prose + the inner_review default change.

**Files:**
- Modify: `commands/goal.md` — lines 5 (flag desc), 60, 155, 170, 222 (inner_review default `haiku`→`auto`); step 5c prose (lines ~160–170) ship-delegates-to-/review; note review.provider must be set.

- [ ] **Step 1: Change inner_review.model default `haiku` → `auto`**

Edit each occurrence in `commands/goal.md` where `INNER_REVIEW_MODEL` default is stated as `"haiku"` (lines 60, 155, 222) to `"auto"`, and in line 155 update the dispatch instruction: the reviewer subagent runs on the resolved tier where `auto` right-sizes by working-tree diff scope (docs→haiku, normal→sonnet, risky→opus); `review-model=<tier>` still overrides. Line 5 flag description: "model for the cheap inner-review pass — `auto` (default, right-sized) or an alias like haiku|sonnet|opus".

- [ ] **Step 2: Update the ship-delegates-to-/review prose**

In `commands/goal.md` step 5c (lines ~160–170), reword "`/ship` … drives the post-PR review loop (with `review.provider=copilot`, steps 13–14)" → "`/ship` delegates the post-PR review loop to `/gh-issue-driven:review`, which writes the same `review.*` state block (`/goal` reads `review.copilot.exit_reason` unchanged)." Keep the done/needs_human mapping exactly.

- [ ] **Step 3: Note the default-none implication**

In `commands/goal.md` (near line 61 / 169 where Copilot optionality is documented), add: "Because `review.provider` now defaults to `none`, `/goal`'s effective config must set `review.provider` (e.g. `copilot`) for the loop to run; otherwise each PR is opened unreviewed (`needs_human`)."

- [ ] **Step 4: Verify**

```bash
grep -n '"haiku"' commands/goal.md            # expect 0 (all flipped to auto, except prose examples like docs→haiku)
grep -n 'delegates the post-PR review loop to' commands/goal.md  # expect 1
grep -n 'defaults to `none`' commands/goal.md  # expect the new note
```
Expected: inner_review defaults flipped; delegation prose present; default-none note present. (The `docs→haiku` heuristic mention is allowed.)

- [ ] **Step 5: Commit**

```bash
git add commands/goal.md
git commit -m "docs(goal): inner_review.model auto default; ship delegates review loop to /review"
```

---

### Task 8: Update `doctor.md` and `status.md`

**Files:**
- Modify: `commands/doctor.md` (any `copilot.enabled` / default-copilot assertion), `commands/status.md` (recap copy for unreviewed PRs)

- [ ] **Step 1: doctor.md — stop treating `copilot.enabled` as authoritative**

```bash
grep -n "copilot.enabled\|review.provider" commands/doctor.md
```
For each hit, reword so `copilot.enabled` is reported as deprecated/ignored and the provider default is `none` (review opt-in). Do **not** touch the `PMRP_GLOB=claude-plugins-official/feature-dev*` line (gate2 code-reviewer path, out of scope).

- [ ] **Step 2: status.md — a PR with no review is normal**

```bash
grep -n "copilot\|review\|provider" commands/status.md
```
Adjust the recap so that `review.provider=none` / no review state renders as `Review: opt-in (run /gh-issue-driven:review)` rather than an anomaly/missing-data warning.

- [ ] **Step 3: Verify**

```bash
grep -n "deprecated\|opt-in\|default.*none" commands/doctor.md commands/status.md
bash tests/test_state_schema.sh   # status reads state; ensure no contract drift
```

- [ ] **Step 4: Commit**

```bash
git add commands/doctor.md commands/status.md
git commit -m "docs(doctor,status): reflect opt-in review + deprecated copilot.enabled"
```

---

### Task 9: Update README + CHANGELOG

**Files:**
- Modify: `README.md`, `README.ja.md`, `CHANGELOG.md`

- [ ] **Step 1: README.md — ship/review flow + Copilot-auto wording**

```bash
grep -nE "Copilot|review\.provider|automatically|ship" README.md | head -40
```
Update the phase-2 / ship description: ship creates the PR; post-PR review is opt-in via `/gh-issue-driven:review`; `review.provider` defaults to `none`; mention new `review.model` (auto). Remove "Copilot fires automatically" claims.

- [ ] **Step 2: README.ja.md — mirror the same edits in Japanese**

```bash
grep -nE "Copilot|review\.provider|自動|ship" README.ja.md | head -40
```
Apply the same content changes, written in Japanese to match the file's style.

- [ ] **Step 3: CHANGELOG.md — add an entry**

Add a top entry (under an Unreleased / next-version heading consistent with the file's format):

```markdown
### Changed
- **Post-PR review is now opt-in.** `review.provider` defaults to `none`; `/ship` creates the PR and stops unless review is explicitly configured or `/goal` runs it. (#83)
- `/ship` delegates the review loop to `/gh-issue-driven:review` (now its canonical home); `ship.md` is ~40% smaller.
- New `review.model` (`auto|haiku|sonnet|opus`, default `auto`) right-sizes the fix-application model. `goal.inner_review.model` default is now `auto`.
- **Deprecated:** `copilot.enabled` is no longer consulted — use `review.provider`.
```

- [ ] **Step 4: Verify**

```bash
grep -n "opt-in\|review.model\|#83" CHANGELOG.md
grep -ni "opt-in\|review.provider" README.md README.ja.md
```

- [ ] **Step 5: Commit**

```bash
git add README.md README.ja.md CHANGELOG.md
git commit -m "docs: document opt-in review, /review canonical loop, review.model (#83)"
```

---

### Task 10: Final verification + acceptance-criteria sweep

**Files:** none (verification only)

- [ ] **Step 1: Full suite green**

Run the FULL SUITE block. Expected: ALL TESTS PASS.

- [ ] **Step 2: No dangling references / no leftover legacy**

```bash
cd /home/jfk/works/gh-issue-driven
echo "--- ship.md must not reference the moved loop internals ---"
grep -nE "JQ_DETECT_FILTER|14\.[a-i]\.|13c\." commands/ship.md || echo "clean"
echo "--- copilot.enabled fully deprecated (only doc mentions allowed) ---"
grep -rn "copilot.enabled" commands/ | grep -v "deprecated\|Deprecated\|no longer\|ignored" || echo "clean"
echo "--- review.md is canonical (has loop + JQ block + autonomous + review.model) ---"
grep -c "JQ_DETECT_FILTER_BEGIN" commands/review.md   # 1
grep -c "AUTONOMOUS" commands/review.md               # >=1
grep -c "review.model\|REVIEW_MODEL" commands/review.md # >=1
echo "--- ship.md size gate ---"
wc -l commands/ship.md   # ~660
```

- [ ] **Step 3: Walk the issue #83 acceptance criteria**

Open `gh issue view 83` and confirm each AC box maps to a committed change:
- provider default none ✔ (Task 5); copilot.enabled removed ✔ (Task 5/6); review.md self-contained ✔ (Task 1); ship delegates ✔ (Task 5); review.md --autonomous ✔ (Task 3); review.model auto ✔ (Task 2); goal inner_review auto ✔ (Task 7); /goal state contract unchanged ✔ (Task 7); test sync ✔ (Task 4); docs ✔ (Tasks 6–9); ship.md ~660 lines ✔ (Task 5 step 5).

- [ ] **Step 4: Hand off to /ship**

The branch is ready. Run `/gh-issue-driven:ship` to gate2 + open the PR for #83. (With the new default, ship will stop after PR; run `/gh-issue-driven:review` if you want the Copilot loop on this PR.)

---

## Notes for the implementer

- **This is a move-not-rewrite for Tasks 1.** The loop content already exists verbatim in `ship.md`; copy it into `review.md` faithfully, adjusting only step-number cross-references. Do not "improve" the logic — behavior must be byte-equivalent except for the documented changes (default none, review.model, autonomous in review.md).
- **Keep the `## Verdict:` / state-enum / JSON-value strings English** — they are parser contracts (see each command's Output language section).
- **The JQ_DETECT_FILTER sentinels must remain unique within review.md** (one BEGIN, one END in a code block; the prose mention elsewhere, if any, must not collide — mirror how ship.md/jq-sync-check handled it).
- **Each task commits independently and leaves the suite green.** If a task can't keep the suite green on its own, reorder rather than batch.
