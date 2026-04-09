---
description: Diagnose the gh-issue-driven environment — verifies gh CLI auth, required plugins, git repo, configuration, and cache directory. Read-only.
arguments:
  - name: input
    description: "Optional: 'verbose' for full output, 'fix' to print 'try this' hints next to failures (never auto-remediates)."
    required: false
---

## Trust boundary

This command is **mostly read-only**. It must not modify any file outside its **single permitted target**:

- `~/.claude/cache/gh-issue-driven/<repo-flat>.copilot-setup.json` — the bounded confirmation cache for the "Copilot review setup" check below. Permitted actions on this single file: **create, refresh (atomic temp + mv), and delete** — and nothing else. The check uses the AskUserQuestion tool to confirm Mode A status; on "Yes" it refreshes the cache, on "No, Mode B" it deletes the cache, on "Skip" it does neither. No other section of doctor writes anywhere.

It must not install anything, change git state, or call any non-read-only tool. Print only `set` / `unset` for token-shaped environment variables — never echo their values.

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

### Copilot review setup (interactive — runs before the rest of the recommended checks)

The Copilot review loop in `/gh-issue-driven:ship` works in two modes. **One must be true** for the loop to function end-to-end:

- **Mode A — Automatic Copilot code review (recommended)**: a per-repo setting at `https://github.com/<owner>/<repo>/settings/code-review`. When enabled, GitHub auto-requests Copilot's review on PR open AND on every push to the PR. The plugin's `--add-reviewer` call becomes redundant (in the good sense). **Works on any `gh` CLI version.**
- **Mode B — Manual via `gh pr edit --add-reviewer @copilot`**: requires `gh` CLI **>= 2.88.0** (the version that added real Copilot reviewer support per the March 2026 changelog). Earlier `gh` versions silently no-op (exit 0, no error, but the API server-side never queues Copilot — see issue #15).

The plugin **cannot** query Mode A's status via REST or GraphQL (verified 2026-04-09: `GET /repos/{o}/{r}` has no field, `code-review-settings` returns 404, `repository` GraphQL type lacks the field). So this check uses a **bounded confirmation cache** instead of an API probe:

#### How the cache works

Cache file: `~/.claude/cache/gh-issue-driven/<repo-flat>.copilot-setup.json` where `<repo-flat>` is `<owner>-<repo>` (slash → dash, lowercased).

Schema:

```json
{
  "schema_version": 1,
  "repo": "<owner>/<repo>",
  "mode_a_confirmed": true,
  "confirmed_at": "<UTC ISO-8601>",
  "expires_at": "<UTC ISO-8601, confirmed_at + 7 days>"
}
```

The 7-day TTL is a fixed const in this command, not a config knob — re-confirming repo settings every 1-day vs 14-day is not a meaningful user preference, and adding a config key would just expand the surface for nobody. To force a re-prompt, delete the cache file directly.

#### Check logic

Read `copilot.skip_setup_prompt` from config. If true, print one line `✅ Copilot setup: prompt skipped (copilot.skip_setup_prompt=true)` and skip to the gh version check at the bottom of this section.

Otherwise:

1. Compute `<repo-flat>` from `gh repo view --json nameWithOwner -q .nameWithOwner` (slash → dash, lowercased).
2. Resolve the cache state into one of two paths:

   **Path A — Cache present and fresh** (cache file exists AND current UTC < `expires_at`):
   - Print one line and skip the prompt:
     ```
     ✅ Copilot setup: Mode A confirmed <confirmed_at> (re-check on <expires_at>)
     ```
   - Continue to the gh version check.

   **Path B — Needs prompt** (cache absent OR cache expired):
   - On expired only, print a one-line preamble:
     ```
     ⚠️  Copilot setup: previous Mode A confirmation expired on <expires_at>
     ```
   - On absent (first run for this repo), print the **full** Copilot setup explanation block:
     ```
     ### Copilot code review setup

     The Copilot review loop in /gh-issue-driven:ship works in two modes. ONE must be enabled:

       Mode A — Automatic (recommended)
         Repo setting: https://github.com/<owner>/<repo>/settings/code-review
         Toggle: ☑ Automatic Copilot code review
         Result: Copilot reviews every PR automatically on create AND on every push.
         Works on any gh CLI version. No manual reviewer add ever needed.

       Mode B — Manual via gh pr edit --add-reviewer @copilot
         Requires: gh CLI >= 2.88.0
         Earlier gh versions silently no-op (issue #15).
     ```
   - On expired (cache existed), skip the long block and print only:
     ```
     Is "Automatic Copilot code review" still enabled at:
       https://github.com/<owner>/<repo>/settings/code-review
     ```
   - In both expired and absent sub-cases, then use the **AskUserQuestion tool** with the same question and options:
     - Question: "Mode A still enabled?"
     - Options: `["Yes", "No, Mode B (gh CLI)", "Skip — set copilot.skip_setup_prompt=true in config to silence"]`
   - Handle the answer (identical for both sub-cases):
     - **"Yes"** → refresh the cache (atomic temp + mv) with `confirmed_at=now`, `expires_at=now + 7 days`. Continue to the gh version check.
     - **"No, Mode B (gh CLI)"** → delete the cache file (so the next run re-prompts). Fall through to the gh version check, which will hard-fail if `gh < 2.88.0`.
     - **"Skip"** → do not refresh, do not delete. Print a hint that setting `copilot.skip_setup_prompt=true` will silence this prompt permanently. Continue to the gh version check.

3. **gh CLI version check** (always runs after the cache logic resolves). Use the same comparison idiom as `commands/ship.md` step 1's pre-flight to keep the two warn-paths in lockstep:

   ```bash
   GH_VER=$(gh --version 2>/dev/null | awk 'NR==1 {print $3}')
   if printf '%s\n%s\n' '2.88.0' "$GH_VER" | sort -V -C 2>/dev/null; then
     GH_VER_OK=true
   else
     GH_VER_OK=false
   fi
   ```

   Three outcomes:

   - `GH_VER_OK=true` → print `✅ gh CLI: $GH_VER (Mode B available)`.
   - `GH_VER_OK=false` AND **Path A** (Mode A confirmed) → print `⚠️  gh CLI: $GH_VER (older than 2.88.0; Mode B unavailable but Mode A is confirmed, so loop will work)`.
   - `GH_VER_OK=false` AND NOT Path A (Mode A unconfirmed / declined / cache absent) → print `❌ gh CLI: $GH_VER (older than 2.88.0; neither mode is available — the Copilot loop will silently skip)`. **This is the only hard error in the Copilot setup section.** Append a `try:` line if `fix` flag is set:
     ```
        try: enable Mode A at https://github.com/<owner>/<repo>/settings/code-review
             OR upgrade gh: https://cli.github.com/
     ```

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
