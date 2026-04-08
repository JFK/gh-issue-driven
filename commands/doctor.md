---
description: Diagnose the gh-issue-driven environment — verifies gh CLI auth, required plugins, git repo, configuration, and cache directory. Read-only.
arguments:
  - name: input
    description: "Optional: 'verbose' for full output, 'fix' to print 'try this' hints next to failures (never auto-remediates)."
    required: false
---

## Trust boundary

This command is **read-only**. It must not modify any file, install anything, change git state, or call any non-read-only tool. Print only `set` / `unset` for token-shaped environment variables — never echo their values.

## Steps

Parse `$ARGUMENTS` for the optional flags `verbose` and `fix`.

Run each check in the order below. For each check print one of:
- `✅ <name>` (passed)
- `⚠️  <name>: <reason>` (warning, recommended but not required)
- `❌ <name>: <reason>` (failed, blocks gh-issue-driven from working)

If `fix` flag is set, append a single `   try: <command>` line beneath each `❌` (and beneath `⚠️` when there's an obvious remediation).

Group checks under three headings: **Required**, **Recommended**, **Informational**.

### Required checks

1. **Inside a git repository**
   ```bash
   git rev-parse --is-inside-work-tree
   ```
   Fail → `not inside a git repo`. fix: `cd into a repository`.

2. **gh CLI installed and authenticated**
   ```bash
   gh --version && gh auth status
   ```
   Fail → `gh missing` or `gh not authenticated`. fix: `gh auth login`.

3. **Current dir resolves to a GitHub repo**
   ```bash
   gh repo view --json nameWithOwner
   ```
   Fail → `not a GitHub repo (or no remote configured)`. fix: `git remote add origin <url>`.

4. **Required PATH dependencies**
   - `git`, `gh`, `jq` must all be on PATH.
   - `python3` is recommended (used by some helper checks).
   For each missing one print a `❌` and `try: apt install <pkg>` / `brew install <pkg>` hint when `fix` is set.

### Recommended checks

5. **Default branch detection**
   ```bash
   gh repo view --json defaultBranchRef -q .defaultBranchRef.name
   ```
   Warn if empty.

6. **Cache directory writable**
   ```bash
   mkdir -p ~/.claude/cache/gh-issue-driven && test -w ~/.claude/cache/gh-issue-driven
   ```
   Fail → `cannot write to ~/.claude/cache/gh-issue-driven`.

7. **Reviewer plugin: `claude-c-suite`**
   - Probe: search for any of `~/.claude/plugins/cache/claude-c-suite*` (glob), or attempt a no-op invocation of the Skill tool with `/claude-c-suite:ask` and detect "skill not found".
   - Warn if missing → `gate1/gate2 will degrade to advisory-only`.

8. **Reviewer plugin: `claude-phd-panel`** (optional but recommended for v0.2 features)
   - Probe via plugin cache glob.
   - Warn if missing — does not block v0.1.0 functionality.

9. **Memory plugin: `kagura-memory`**
   - Probe: check if the `mcp__kagura-memory__recall` tool is callable, OR glob `~/.claude/plugins/cache/*kagura-memory*`.
   - Warn if missing → `recall and session-start/summary will be skipped`.

### Informational checks

10. **Working tree clean**
    ```bash
    test -z "$(git status --porcelain)"
    ```
    Warn if dirty (but `start` would refuse anyway — this is an early heads-up).

11. **Configuration file**
    ```bash
    test -f ~/.claude/gh-issue-driven-config.json && jq empty ~/.claude/gh-issue-driven-config.json
    ```
    - Missing → informational, defaults will be used. Hint: `/gh-issue-driven:config init`.
    - Present but unparseable → warn with the `jq` error.

12. **gh API scope check**
    ```bash
    gh api user --jq .login
    ```
    Just to confirm the auth has API access.

13. **Copilot reviewer reachability** (informational, may be unsupported on some plans)
    ```bash
    gh api repos/:owner/:repo/collaborators 2>/dev/null | grep -q copilot
    ```
    Print `✅` / `⚠️ Copilot reviewer not detected — may still work via @copilot mention`.

14. **Stale state files**
    List `~/.claude/cache/gh-issue-driven/*.json` and check whether the corresponding branch (decoded from filename) still exists locally:
    ```bash
    git show-ref --verify --quiet refs/heads/<branch>
    ```
    Print a count of stale entries. Suggest cleanup:
    ```
       try: rm ~/.claude/cache/gh-issue-driven/<stale-file>.json  (manual)
    ```
    Never auto-delete.

### Final summary

After all checks, print one of:

```
All required checks passed. (X warnings, Y informational notes)
```

or:

```
N required check(s) failed — see above. gh-issue-driven will not run until these are resolved.
```

If `verbose` flag is set, also dump the effective configuration (deep-merged user + defaults) at the end.

---

> ⚠️ **Read-only diagnostic**: This command never modifies anything. The `fix` flag only adds suggested commands to the output — you must run them yourself.
