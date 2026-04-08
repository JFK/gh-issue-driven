---
description: Show gh-issue-driven state for the current branch — phase, gate verdicts, PR status, Copilot loop count. Read-only.
arguments:
  - name: branch
    description: "Optional: branch name to inspect. Defaults to the current branch. Pass 'all' to list every cached state file as a one-line table."
    required: false
---

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
        - audit:    <pass|fail>
        - cso:      <verdict>
        - qa-lead:  <verdict>
        - cto:      <verdict>
        Full output: <summary_path>

PR      <pr_url>  (#<number>, opened <relative time ago>)
        Live state: <reviewDecision from gh pr view>
        ... or ... (no PR yet)

Copilot Loop <loops_run>/<max_loops>, last state: <last_state>
        Last polled: <relative time>
```

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
