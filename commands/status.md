---
description: Show gh-issue-driven state for the current branch — phase, gate verdicts, PR status, Copilot loop count. Read-only.
arguments:
  - name: branch
    description: "Optional: branch name to inspect. Defaults to the current branch. Pass 'all' to list every cached state file as a one-line table. Pass 'proposals' to list retained proposal state files under ~/.claude/cache/gh-issue-driven/proposals/."
    required: false
---

## Output language

Load `lang` just-in-time from `~/.claude/gh-issue-driven-config.json` (default `"en"` if the file is missing, unparseable, or doesn't set `lang`). status.md is read-only and short, so this is a minimal one-key read — no full deep-merge of all config defaults is needed for this command.

When `lang != "en"`, produce the pretty-printed status block in the language specified by `lang` — the section labels (`Issue`, `Branch`, `Phase`, `Gate1`, `Gate2`, `PR`, `Copilot Loop`, `Exit`, `Detection`, `Last polled`) stay English (they map directly to state JSON field names), but the prose around them, the silent_no_op hint footer, and the `all` mode footer line are localized.

What stays English regardless of `lang`:

- State JSON field names and enum values (`green`, `yellow`, `red`, `pass`, `fail`, `silent_no_op`, etc.) — Layer C
- Branch names, PR URLs, file paths, summary_path values
- The verdict and phase tokens themselves

## Trust boundary

**Read-only.** This command must not modify any state file, never call `gh pr edit` or any mutating gh subcommand, and never delete cache entries. It may call `gh pr view` (read-only) to fetch the live `reviewDecision`.

## Steps

### 1. Resolve the branch

- If `$ARGUMENTS` is empty: use `git rev-parse --abbrev-ref HEAD`.
- If `$ARGUMENTS == "all"`: skip to the "all" mode below.
- If `$ARGUMENTS == "proposals"`: skip to the "proposals" mode below.
- Otherwise: use `$ARGUMENTS` as the branch name verbatim.

### 2. Locate the state file

`STATE_PATH=~/.claude/cache/gh-issue-driven/$(echo "$BRANCH" | tr '/' '-').json`

If the file does not exist:

```
no gh-issue-driven state for branch <branch>

Run /gh-issue-driven:start <issue> to begin tracking this branch.
```

Then exit.

### 3. Pretty-print the state

Read the JSON. Extract issue data using the same v1/v2 compatibility logic as `ship.md` step 1b: if `state.issues` array exists, use it; otherwise synthesize from `state.issue_number`/`state.issue_title`/`state.issue_url`.

Print a single block:

```
<if state.issues has more than 1 entry:>
Issues  #<n1> <title1>
        #<n2> <title2>
        #<n3> <title3>
        ...
<else:>
Issue   #<num> <title>
        <url>
</if>
Repo    <repo>
Branch  <branch>  (type: <type>)
Phase   <phase>   (started <relative time ago>)

Gate1   <verdict>  (via /<reviewer>[, escalated to /ceo])
        Full output: <summary_path>

Gate2   <aggregate verdict>
        - audit:       <pass|fail|skipped|unknown>   ← see audit value semantics below
        - binary_gate: <skill name or "(none)">  ← omit this line if state lacks the field (older state files)
        <for each key in sorted keys of advisor_verdicts:>
        - <key>: <advisor_verdicts[key]>
        </for>
        Full output: <summary_path>

PR      <pr_url>  (#<number>, opened <relative time ago>)
        Live state: <reviewDecision from gh pr view>
        ... or ... (no PR yet)

Review  provider: <review.provider>
        Total loops: <review.total_loops_run>
        Providers completed: <review.providers_completed>
        <if review.code_review exists:>
        /code-review: <findings_addressed> addressed, <findings_skipped> skipped (ran <relative time ago>)
        <if review.copilot exists:>
        Copilot: <review.copilot.loops_run>/<review.copilot.max_loops>, last state: <review.copilot.last_state>
        Detection: <review.copilot.detection_method>   ← (omit line if absent in state)
        Exit:      <review.copilot.exit_reason>        ← (omit line if absent / loop still in progress)
        HITL:      <review.copilot.hitl_decision>      ← (omit line if null or absent — backward compat with v0.2.x state files)
        HITL confirmed: <relative time of hitl_confirmed_at>  ← (omit line if hitl_confirmed_at is null or absent)
        Threads:   <review.copilot.threads_replied> replied, <review.copilot.threads_resolved> resolved  ← (omit line if both absent — backward compat)
        Last polled: <relative time>
```

The `Detection` and `Exit` lines are produced by `commands/ship.md` step 13 and step 14. They are the post-mortem signal for "did the loop run, and if not, why" — see ship.md step 14.g for the field semantics. If the state file does not have these fields (e.g. the branch was started before they existed, or the loop is still mid-iteration), omit the corresponding line rather than printing `null`.

The `HITL` and `HITL confirmed` lines are produced by `ship.md` step 13c (the HITL invocation gate). They are the operator's decision signal — "confirmed" means the operator explicitly OK'd Copilot invocation, "declined" means they chose to skip this run (paired with `exit_reason=hitl_declined` and `loops_run=0`). Omit both lines when `hitl_decision` is `null` or absent — this handles (a) state files written before v0.3.0, (b) runs where `copilot.hitl_confirm_invocation=false` disabled the gate, (c) runs where `DRY_RUN` skipped the gate, and (d) code-review-only paths where the gate was never reached.

When `exit_reason == "silent_no_op"`, also append a one-line hint. Since v0.3.0, the hint wording changes with context: when `hitl_decision == "confirmed"` (the operator confirmed Copilot and Copilot still did not respond), the hint is **"Copilot review was confirmed but did not respond — this is unusual. Check the PR state, verify Copilot is active, or rerun with `/gh-issue-driven:review`."** When `hitl_decision` is `null` (gate was disabled or bypassed), use the legacy hint: **"run `/gh-issue-driven:doctor` to verify Mode A or upgrade gh"**.

#### Review block — v1/v2 schema compatibility

The post-PR review state has two schema versions:

- **v2** (v0.2.0+): `review` is a top-level block with `provider`, `total_loops_run`, `providers_completed`, and optional `copilot`/`code_review` sub-blocks.
- **v1** (v0.1.x): `copilot` is a top-level block with `loops_run`, `max_loops`, `last_state`, etc. No `review` block exists.

Reader logic: if `review` exists, use it directly. Otherwise, synthesize from legacy `copilot` block: `{ provider: "copilot", total_loops_run: copilot.loops_run, providers_completed: ["copilot"], copilot: { ...legacy fields } }`. Skip any field that is absent. This allows `/status` to render both old and new state files without migration.

#### `gate2.audit` value semantics

The `audit` field in the persisted state can take **four** values:

| Value | Meaning |
|---|---|
| `pass` | Binary gate skill ran cleanly and returned `## Verdict: pass` (or the heuristic derived `pass` from the markdown body). The gate2 binary check succeeded. State written by ship.md step 10's normal flow. |
| `fail` | Binary gate skill ran cleanly and returned `## Verdict: fail` (or the heuristic derived `fail` from BLOCKER/MUST FIX tokens). **Hard release block** — even FORCE cannot override. **State IS persisted** by ship.md step 7's hard-abort path: step 7 explicitly writes `gate2.audit=fail, gate2.binary_gate=<skill>, gate2.verdict=red` to the state file BEFORE calling exit, so `/status` can show the failed verdict and the gate2 markdown after the abort. This is a partial step-7 write, not waiting for step 10. |
| `skipped` | `gate2.binary_gate` was `null` (advisor-only mode, the v0.1.1 default). The binary gate slot was never invoked. The gate2 verdict is determined purely by the advisor aggregate. This is the common case for any non-claude-c-suite-plugin user. State written by step 10's normal flow. |
| `unknown` | `gate2.binary_gate` was configured to a skill name, but the skill errored or was unavailable. **Two write paths**: (a) without FORCE, ship.md step 7 aborts and writes a partial state with `audit=unknown` so `/status` can show the abort reason; (b) with FORCE, step 7 logs a loud warning and proceeds to step 10's normal flow which persists `audit=unknown` as a diagnostic. Either way, `unknown` means "the binary gate didn't actually validate the PR — either it wasn't run (the skill broke) or the operator force-overrode it." If you see `unknown` in production state, the binary gate skill probably had a bug or wasn't installed. Investigate. |

If the state file lacks the `audit` field entirely (older state files written before the binary gate refactor), render as `(absent)` and don't fail.

#### Advisor verdicts — v1/v2 schema compatibility

The `gate2` section has two schema versions for advisor verdicts:

- **v2** (v0.1.2+): `gate2.advisor_verdicts` is a map keyed by skill name (e.g. `{"cso": "green", "qa-lead": "yellow", "cto": "green"}`). Iterate it to render one `- <skill_name>: <verdict>` line per advisor.
- **v1** (v0.1.0–v0.1.1): advisor verdicts are stored as named fields `gate2.cso`, `gate2.qa_lead`, `gate2.cto`. No `advisor_verdicts` field exists.

Reader logic: if `gate2.advisor_verdicts` exists, use it directly. Otherwise, synthesize the map from v1 fields: `{"cso": gate2.cso, "qa-lead": gate2.qa_lead, "cto": gate2.cto}` (skip any field that is absent). This allows `/status` to render both old and new state files without migration.

For the live PR state, run:

```bash
gh pr view <pr_number> --json reviewDecision,state,mergeable -q '"\(.state) / reviewDecision: \(.reviewDecision) / mergeable: \(.mergeable)"'
```

Wrap in `2>/dev/null || echo '(could not fetch live state)'` so this never fails the command.

### 4. Mode `all`

If `$ARGUMENTS == "all"`:

1. Glob `~/.claude/cache/gh-issue-driven/*.json`.
2. For each file, parse the JSON and print one row:

   ```
   <branch> | <phase> | gate1=<verdict> | gate2=<aggregate> | review=<provider> | pr=#<num or ->
   ```

3. Sort by `started_at` descending.
4. Print a footer line: `<count> tracked branches.`
5. If any row has `(.review.copilot.exit_reason // .copilot.exit_reason) == "silent_no_op"`, append a single hint after the footer:
   `Hint: <N> branch(es) hit Copilot silent_no_op — run /gh-issue-driven:doctor to verify Mode A or upgrade gh.`
   The v1/v2 compatible path (`review.copilot.exit_reason` first, fall back to legacy `copilot.exit_reason`) mirrors the single-branch reader logic above — without this, v2 state files never trigger the hint.

### 5. Mode `proposals`

If `$ARGUMENTS == "proposals"`:

1. Glob `~/.claude/cache/gh-issue-driven/proposals/*.json`. If the directory does not exist or contains no JSON files, print `no proposals found` and exit.
2. For each file, parse the JSON. Print one row:

   ```
   <slug> | <phase> | review=<review.verdict> | dedup=<dedup.candidates length> | <created_at>
   ```

3. Sort by `created_at` descending.
4. Print a footer: `<count> saved proposal(s). Proposals are stored at ~/.claude/cache/gh-issue-driven/proposals/.`

Note: successful proposals are not written to disk after issue creation (see `propose.md` step 12), and dry-run proposals are never written to disk, so this mode typically shows only retained proposals (aborted, review_failed, create_failed).

### 6. Hint footer

After the per-branch output, print:

```
View full reviewer output:
  cat <gate1_summary_path>
  cat <gate2_summary_path>

Run /gh-issue-driven:doctor if anything looks wrong.
```

---

> ⚠️ **Read-only**: This command never modifies state. It calls `gh pr view` for the live PR decision but does not touch the PR or the local repo.
