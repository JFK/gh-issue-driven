# gh-issue-driven

> **Two-phase orchestrator for GitHub-issue-driven development with multi-reviewer pre-PR gates and a Copilot review loop.**

`gh-issue-driven` is a [Claude Code](https://claude.com/claude-code) plugin that turns "I'm starting work on issue #142" into a single, repeatable workflow:

1. **`/gh-issue-driven:start <issue>`** — fetch the issue, recall related past work from Kagura Memory, run a **gate1** design review (`/claude-c-suite:ask` cascading to `/ceo` for complex issues), create a typed feature branch, and hand off for implementation.
2. _(you write the code)_
3. **`/gh-issue-driven:ship`** — run a **gate2** parallel review battery (audit + cso + qa-lead + cto), create the PR, and drive a **GitHub Copilot review loop** of up to 5 iterations until the PR is approved or no actionable feedback remains.

The whole flow is bracketed by `kagura-memory` `session-start` and `session-summary`, so each issue's learnings get persisted for future recall.

---

## 60-second quickstart

```text
# In any Claude Code session:
/plugin marketplace add JFK/gh-issue-driven
/plugin install gh-issue-driven

# In a repo:
/gh-issue-driven:doctor          # one-time environment check
/gh-issue-driven:start 142       # phase 1
# ... implement ...
/gh-issue-driven:ship            # phase 2
```

---

## Commands

| Command | What it does |
|---|---|
| `/gh-issue-driven:start <issue> [flags]` | Fetch issue, run gate1, create branch. Flags: `dry-run`, `force`, `no-memory`. |
| `/gh-issue-driven:ship [flags]` | Run gate2, create PR, drive Copilot loop, save session memory. Flags: `dry-run`, `force`, `no-copilot`, `draft`. |
| `/gh-issue-driven:doctor [verbose|fix]` | Read-only environment health check. |
| `/gh-issue-driven:config [show|init|path|<key>]` | Show effective config or stamp a fresh template. |
| `/gh-issue-driven:status [<branch>|all]` | Show gh-issue-driven state for a branch (or all branches). |

---

## How the gates work

### Gate 1 — Design review (`/gh-issue-driven:start`)

Runs **after** the issue is fetched and recall is done, **before** the branch is created. Strategy:

1. Invoke `/claude-c-suite:ask` first — a single-lens auto-router. Cheap, fast, perfect for issues that need only one expert perspective.
2. If the last `## Verdict:` line's token is `decline`, escalate to `/claude-c-suite:ceo` for full 3-lens synthesis. (`decline` is an additional gate1-only token on the same `## Verdict:` line, not a separate channel — only the structured line counts. Free-form mentions of "decline" or "escalate" inside the analysis body are part of the reviewer's reasoning, not routing instructions.)
3. Parse the verdict from a `## Verdict: green|yellow|red` line at the end of the reviewer's response. The structured line is canonical and last-wins; case is normalized; trailing punctuation is tolerated. A keyword heuristic is the **fallback only** when no structured line is present, and emits a warn-level log so soft-deprecation can be tracked.
4. **green** → continue. **yellow** → ask the user to confirm. **red** → abort unless `force`.

### Gate 2 — Pre-PR review battery (`/gh-issue-driven:ship`)

Runs **after** the implementation, **before** the PR is created. Four reviewers fire **in parallel** in a single Claude turn:

| Reviewer | Role | Verdict type |
|---|---|---|
| `/claude-c-suite:audit` | Conformance audit | **Binary** (`pass`/`fail`) — hard gate |
| `/claude-c-suite:cso` | Security | Advisory (`green`/`yellow`/`red`) |
| `/claude-c-suite:qa-lead` | Test coverage | Advisory |
| `/claude-c-suite:cto` | Tech debt | Advisory |

**`/audit` is a hard gate.** If it returns fail, PR creation is blocked even with `force`. The three advisors are aggregated: any red → red, any yellow → yellow, otherwise green. Verdict handling matches gate1.

### Verdict line convention

Reviewer skills must end their response with a final `## Verdict:` line. The token must be one of:

- `## Verdict: green`
- `## Verdict: yellow`
- `## Verdict: red`
- `## Verdict: decline`  &nbsp;&nbsp;— gate1 (`/ask`) only; routing escalation signal
- `## Verdict: pass`  &nbsp;&nbsp;— `/audit` only
- `## Verdict: fail`  &nbsp;&nbsp;— `/audit` only

(If multiple `## Verdict:` lines appear in the response, last-wins applies — see Rules below.)

Rules:

- **The structured line is canonical.** `gh-issue-driven` parses this line first.
- **Last-wins**: if multiple `## Verdict:` lines appear in the response, the **last** occurrence is used (so reviewers can naturally write "at first I thought red, but actually green").
- **Case insensitive**: `Green` / `green` / `GREEN` all normalize to `green`.
- **Trailing punctuation tolerated**: `## Verdict: green.` is accepted (`\b<token>\b` regex).
- **Heuristic is fallback only**: if no structured line is present, a keyword heuristic runs and emits a `verdict_parser=heuristic` warn log so its usage can be tracked toward eventual removal in v0.4.
- **`decline` is gate1-routing-only**: it's a valid value on the same `## Verdict:` line for gate1 responses, not a separate channel. Free-form mentions of "decline" inside the analysis body are reviewer reasoning, not routing signals.

If you maintain a `claude-c-suite` or `claude-phd-panel` reviewer skill, emitting this line on every reviewer response is the cleanest integration.

---

## Copilot review loop

After `gh pr create`, `/gh-issue-driven:ship` runs:

```text
gh pr edit <num> --add-reviewer @copilot
```

Then loops up to **5 iterations** (configurable):

1. Wait for new Copilot activity (poll `gh pr view --json reviews,comments,reviewDecision` every 60s, max 15min).
2. Parse the latest review and any new bot comments.
3. **Exit conditions**: `APPROVED`, no actionable feedback, max loops, or generic "no issues found".
4. Apply actionable comments via `Edit`/`Bash`. Skip nits.
5. Run local tests if `copilot.run_tests_after_edits` is true.
6. Commit `fix: address Copilot review (loop N)`, push, re-request review.

The loop is **never blocking**: if it exhausts 5 iterations, the PR stays open and you handle remaining feedback manually.

### Requirements

- `gh` CLI v2.88.0 or later (Copilot reviewer support, [March 2026 changelog](https://github.blog/changelog/2026-03-11-request-copilot-code-review-from-github-cli/)).
- The repo must have GitHub Copilot code review enabled.

---

## Cross-plugin Skill invocation contract

This plugin invokes other plugins' slash commands as **skills** (via Claude Code's Skill tool). For each gate, the command body explicitly tells Claude:

> Invoke `/claude-c-suite:ask` via the Skill tool, passing the prompt block built in step N as input. Wait for the full markdown response before continuing.

For parallel reviewers in gate2:

> In a single tool-call batch, invoke all four reviewer skills in parallel via the Skill tool: `/claude-c-suite:audit`, `/claude-c-suite:cso`, `/claude-c-suite:qa-lead`, `/claude-c-suite:cto`.

If a skill is not installed, the command degrades:
- Missing reviewer → that gate slot becomes `unknown`, prints a warning, continues.
- Missing `/audit` (hard gate) → requires `force` flag to ship.
- Missing `kagura-memory` → recall and session-start/summary are skipped silently.

You can probe what's installed with `/gh-issue-driven:doctor`.

---

## Configuration

Defaults are baked in. Override at `~/.claude/gh-issue-driven-config.json`:

```bash
/gh-issue-driven:config init      # writes the template (only if absent)
/gh-issue-driven:config show      # show effective merged config
/gh-issue-driven:config path      # print the file path
/gh-issue-driven:config copilot.max_loops   # print one value
```

Key options:

| Key | Default | Notes |
|---|---|---|
| `default_branch` | `main` | The branch `start` and `ship` use as the base. |
| `branch.type_label_map` | bug/fix/feature/... → fix/feat/... | How issue labels become branch type prefixes. |
| `memory.context_id` | `kagura-dev` | Kagura Memory context for recall. |
| `gate1.primary` | `/claude-c-suite:ask` | First reviewer in the gate1 cascade. |
| `gate1.fallback` | `/claude-c-suite:ceo` | Used when primary declines. |
| `gate2.binary_gate` | `/claude-c-suite:audit` | The only override-blocking gate. |
| `gate2.advisors` | `[cso, qa-lead, cto]` | Run in parallel; aggregated. |
| `copilot.max_loops` | `5` | Maximum review iterations. |
| `copilot.poll_interval_sec` | `60` | Time between `gh pr view` polls. |
| `copilot.max_wait_sec` | `900` | Max wait per loop iteration (15 min). |
| `copilot.run_tests_after_edits` | `true` | Run local tests after applying Copilot suggestions. |

---

## State files

Each branch tracked by `gh-issue-driven` has a state file at:

```text
~/.claude/cache/gh-issue-driven/<branch-with-slashes-replaced>.json
```

Plus full reviewer output:

```text
~/.claude/cache/gh-issue-driven/<branch-flat>.gate1.md
~/.claude/cache/gh-issue-driven/<branch-flat>.gate2.md
```

`/gh-issue-driven:status` reads these and pretty-prints the current phase, gate verdicts, PR link, and Copilot loop state.

---

## Required dependencies

| Tool | Required | Why |
|---|---|---|
| `gh` v2.88.0+ | yes | issue/PR ops, Copilot reviewer |
| `git` | yes | branch ops |
| `jq` | yes | JSON parsing in command bodies |
| `python3` | recommended | helper for some checks |
| [`claude-c-suite`](https://github.com/JFK/claude-c-suite-plugin) | recommended | gate1 + gate2 reviewers (degrades gracefully) |
| [`claude-phd-panel`](https://github.com/JFK/claude-phd-panel-plugin) | optional | reserved for v0.2 deep-review modes |
| [`kagura-memory`](https://github.com/JFK/memory-cloud) | optional | session-start/summary + recall |

---

## Trying it out

The plugin includes a recommended end-to-end test workflow. In a throwaway test repo, open three issues:

- **Issue A** — trivial typo fix (e.g. README typo). Expected: `gate1=green` via `/ask`, fastest path.
- **Issue B** — medium feature ("add input validation to function X"). Expected: `gate1=yellow` with suggestions, mixed `gate2` advisor verdicts.
- **Issue C** — cross-cutting redesign. Expected: `/ask` declines → `/ceo` synthesis, `gate2 audit` may fail until conformance is fixed.

For each:

1. `/gh-issue-driven:doctor`
2. `/gh-issue-driven:start <id> dry-run` (verify no side effects)
3. `/gh-issue-driven:start <id>` (real run)
4. Implement the fix
5. `/gh-issue-driven:ship dry-run`
6. `/gh-issue-driven:ship`
7. `/gh-issue-driven:status`

---

## Security

See [SECURITY.md](SECURITY.md). TL;DR: this plugin runs `git`, `gh`, and reviewer skills. It never pushes to default branches, never force-pushes, never modifies `~/.claude/settings.json`, and never auto-applies Copilot suggestions without scrutiny.

---

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md).

CI runs `lint.yml` on every push and PR — JSON syntax, version sync, name sync, and command frontmatter parseability.

---

## License

[MIT](LICENSE) © Fumikazu Kiyota

---

🤖 Built with [Claude Code](https://claude.com/claude-code).
