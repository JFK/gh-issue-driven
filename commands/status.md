---
description: Show gh-issue-driven state for the current branch — phase, gate verdicts, PR status, Copilot loop count. Read-only.
arguments:
  - name: branch
    description: "Optional: branch name to inspect. Defaults to the current branch. Pass 'all' to list every cached state file as a one-line table."
    required: false
---

## Output language

Load `lang` just-in-time from `~/.claude/gh-issue-driven-config.json` (default `"en"` if the file is missing, unparseable, or doesn't set `lang`). status.md is read-only and short, so this is a minimal one-key read — no full deep-merge of all config defaults is needed for this command.

When `lang == "ja"`, produce the pretty-printed status block in Japanese — the section labels (`Issue`, `Branch`, `Phase`, `Gate1`, `Gate2`, `PR`, `Copilot Loop`, `Exit`, `Detection`, `Last polled`) stay English (they map directly to state JSON field names), but the prose around them, the silent_no_op hint footer, and the `all` mode footer line are localized.

What stays English regardless of `lang`:

- State JSON field names and enum values (`green`, `yellow`, `red`, `pass`, `fail`, `silent_no_op`, etc.) — Layer C
- Branch names, PR URLs, file paths, summary_path values
- The verdict and phase tokens themselves

This is a minimal v0.1.1 implementation (Option A). The full 3-layer policy with template-level localization is tracked as #19 (v0.1.2).

## Trust boundary

**Read-only.** This command must not modify any state file, never call `gh pr edit` or any mutating gh subcommand, and never delete cache entries. It may call `gh pr view` (read-only) to fetch the live `reviewDecision`.

## Steps

### 1. Resolve the branch

- If `$ARGUMENTS` is empty: use `git rev-parse --abbrev-ref HEAD`.
- If `$ARGUMENTS == "all"`: skip to the "all" mode below.
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

Read the JSON. Print a single block:

```
Issue   #<num> <title>
        <url>
Repo    <repo>
Branch  <branch>  (type: <type>)
Phase   <phase>   (started <relative time ago>)

Gate1   <verdict>  (via /<reviewer>[, escalated to /ceo])
        Full output: <summary_path>

Gate2   <aggregate verdict>
        - audit:       <pass|fail|skipped|unknown>   ← see audit value semantics below
        - binary_gate: <skill name or "(none)">  ← omit this line if state lacks the field (older state files)
        - cso:         <verdict>
        - qa-lead:     <verdict>
        - cto:         <verdict>
        Full output: <summary_path>

PR      <pr_url>  (#<number>, opened <relative time ago>)
        Live state: <reviewDecision from gh pr view>
        ... or ... (no PR yet)

Copilot Loop <loops_run>/<max_loops>, last state: <last_state>
        Detection: <detection_method>   ← (omit line if absent in state)
        Exit:      <exit_reason>        ← (omit line if absent / loop still in progress)
        Last polled: <relative time>
```

The `Detection` and `Exit` lines are produced by `commands/ship.md` step 13 and step 14. They are the post-mortem signal for "did the loop run, and if not, why" — see ship.md step 14.g for the field semantics. If the state file does not have these fields (e.g. the branch was started before they existed, or the loop is still mid-iteration), omit the corresponding line rather than printing `null`. When `exit_reason == "silent_no_op"`, also append a one-line hint pointing at `/gh-issue-driven:doctor` so the operator can confirm Mode A or upgrade gh.

#### `gate2.audit` value semantics

The `audit` field in the persisted state can take **four** values:

| Value | Meaning |
|---|---|
| `pass` | Binary gate skill ran cleanly and returned `## Verdict: pass` (or the heuristic derived `pass` from the markdown body). The gate2 binary check succeeded. |
| `fail` | Binary gate skill ran cleanly and returned `## Verdict: fail` (or the heuristic derived `fail` from BLOCKER/MUST FIX tokens). **Hard release block** — even FORCE cannot override. State is persisted only if FORCE'd past step 7's hard-abort path (which it never is, since `fail` is unconditional abort). |
| `skipped` | `gate2.binary_gate` was `null` (advisor-only mode, the v0.1.1 default). The binary gate slot was never invoked. The gate2 verdict is determined purely by the advisor aggregate. This is the common case for any non-claude-c-suite-plugin user. |
| `unknown` | `gate2.binary_gate` was configured to a skill name, but the skill errored or was unavailable at invocation time AND the operator passed FORCE to continue past step 7's "AUDIT_VERDICT == unknown" abort branch. The binary gate didn't actually validate the PR — the operator overrode it because they trust the change. Persisted as a diagnostic so post-mortem can identify "this PR was force-shipped without binary gate validation." If you see `unknown` in production state, it usually means the binary gate skill had a bug or wasn't installed. Investigate. |

If the state file lacks the `audit` field entirely (older state files written before the binary gate refactor), render as `(absent)` and don't fail.

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
   <branch> | <phase> | gate1=<verdict> | gate2=<aggregate> | pr=#<num or ->
   ```

3. Sort by `started_at` descending.
4. Print a footer line: `<count> tracked branches.`
5. If any row has `copilot.exit_reason == "silent_no_op"`, append a single hint after the footer:
   `Hint: <N> branch(es) hit Copilot silent_no_op — run /gh-issue-driven:doctor to verify Mode A or upgrade gh.`

### 5. Hint footer

After the per-branch output, print:

```
View full reviewer output:
  cat <gate1_summary_path>
  cat <gate2_summary_path>

Run /gh-issue-driven:doctor if anything looks wrong.
```

---

> ⚠️ **Read-only**: This command never modifies state. It calls `gh pr view` for the live PR decision but does not touch the PR or the local repo.
