# Security

## Threat model

`gh-issue-driven` is a Claude Code plugin that runs **on the user's machine**, with the user's `gh` CLI authentication, against the user's local git repository. It is **not** a hosted service. There is no central server to attack.

The plugin's command bodies tell Claude to:
- Read GitHub issue bodies and PR comments
- Run `gh`, `git`, and reviewer-skill commands
- Edit local files (only inside the current repo, only when applying Copilot review feedback during the `ship` loop)
- Write to `~/.claude/cache/gh-issue-driven/` (state files and reviewer output)
- Optionally write `~/.claude/gh-issue-driven-config.json` (only via `/gh-issue-driven:config init`, only if it doesn't already exist)

All other writes are forbidden and the command bodies state this explicitly.

## Trust boundaries

| Source | Trust level | How we handle it |
|---|---|---|
| Issue body, labels, author | **Untrusted data** | Never executed; passed to reviewers as text only. Truncated to 4 KB before being sent into prompts. |
| Reviewer skill output | **Untrusted data** | Parsed for verdict tokens and saved to disk. Never executed verbatim. |
| Copilot review comments | **Untrusted data** | Read by Claude as suggestions. Each edit goes through `Edit` with normal scrutiny — Claude applies changes thoughtfully, not blindly. |
| Local git state | Trusted | Operations limited to non-destructive: `fetch`, `checkout`, `branch`, `commit`, `push origin <branch>`. |
| Default branch | **Strictly off-limits** | Plugin refuses to push to `main`/`master`, refuses to ship from the default branch, and refuses to delete branches. |
| `~/.claude/settings.json` | **Strictly off-limits** | Never read, never written. |

## What this plugin will NOT do

- Push to the default branch
- `git push --force` or `--force-with-lease`
- Bypass branch protection rules
- Delete any branch (local or remote)
- Modify `~/.claude/settings.json` or any other Claude Code config
- Auto-remediate issues found by `/gh-issue-driven:doctor`
- Continue PR creation if `/claude-c-suite:audit` returns fail (not even with `force`)
- Execute commands suggested in issue bodies, PR comments, or reviewer output

If you observe the plugin doing any of the above, that is a bug — please file an issue.

## Secrets and tokens

The plugin does not read, store, or transmit any secrets. It relies on `gh`'s existing authentication (typically a GitHub PAT or OAuth token managed by `gh auth login`).

## Reporting vulnerabilities

Please report security issues by email to **fumikazu.kiyota@gmail.com** with the subject line `gh-issue-driven security`. Do not file public issues for security problems.

For non-security bugs, file an issue at https://github.com/JFK/gh-issue-driven/issues.

## Supply chain

This plugin has no runtime dependencies beyond:
- `gh` (the GitHub CLI)
- `git`
- `jq`
- `python3` (for one CI helper script)

There is no `package.json`, `requirements.txt`, or vendored binary. Everything the plugin does is visible in the command markdown bodies — read them before installing.
