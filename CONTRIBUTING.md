# Contributing to gh-issue-driven

Thanks for your interest! This plugin is a thin orchestration layer over `gh`, `git`, and several reviewer plugins. Most contributions will land in `commands/*.md`.

## Layout

```
.claude-plugin/
  plugin.json            ← name, version, keywords
  marketplace.json       ← marketplace listing (version must stay in sync)
commands/
  start.md               ← Phase 1 orchestrator
  ship.md                ← Phase 2 orchestrator + Copilot loop
  doctor.md              ← read-only env check
  config.md              ← config show/init/get
  status.md              ← state file pretty-printer
.github/workflows/
  lint.yml               ← CI: JSON syntax, version sync, frontmatter parse
  check-frontmatter.py   ← used by lint.yml
README.md / README.ja.md
SECURITY.md / LICENSE / .gitignore
```

There is intentionally no `scripts/` directory in v0.1.0 — every algorithm lives in the command markdown body. If a single command body grows past ~400 lines, that is the signal to extract a helper.

## Local development

This is not a code project — there's nothing to build. To validate your changes:

```bash
# JSON syntax
jq empty .claude-plugin/plugin.json
jq empty .claude-plugin/marketplace.json

# Version sync
test "$(jq -r .version .claude-plugin/plugin.json)" \
   = "$(jq -r .plugins[0].version .claude-plugin/marketplace.json)"

# Frontmatter parses (matches CI)
python3 .github/workflows/check-frontmatter.py
```

To try the plugin in a sandbox without publishing:

```bash
# In any Claude Code session
/plugin marketplace add ./path/to/gh-issue-driven
/plugin install gh-issue-driven
```

Then `/gh-issue-driven:doctor` in a real repo.

## Editing a command

Each command file has YAML frontmatter (`description`, optional `arguments`) followed by a markdown body. The body is the **prompt Claude executes** when the user invokes the slash command. Treat it as production code:

- Be explicit about every Skill/Bash/Edit invocation Claude should make.
- State trust boundaries up front (data vs. instructions).
- For non-trivial steps, write step-by-step pseudocode rather than freeform prose.
- For cross-plugin Skill calls, use the exact phrasing **"Invoke `/plugin:command` via the Skill tool"** so Claude reliably uses the Skill tool rather than inlining its own reasoning.

## Reviewer skill contract

The reviewer skills (`/claude-c-suite:*`, `/claude-phd-panel:*`) are advisory by default. To make them gate-friendly, encourage reviewers to end their response with:

```
## Verdict: green
```

(or `yellow`, `red`, or `pass`/`fail` for `/audit`). `gh-issue-driven` looks for this line first; without it, falls back to keyword heuristics that may not classify perfectly.

If you maintain a c-suite or phd-panel skill, **adding the Verdict line is the single highest-leverage change** for `gh-issue-driven` integration.

## Releasing

Releases have two parts: the **release checklist** (dogfooding gate, below) and the mechanical tag-and-push ceremony (`/gh-issue-driven:tag` automates steps 1–5).

### Release checklist — dogfooding gate

**Rule**: before cutting any `v*` tag, `/gh-issue-driven:start` + `/gh-issue-driven:ship` must be run end-to-end against representative issues. Output evidence from each run is attached to the release notes. The purpose is to make dogfooding a hard gate, not a hope — each release proves the plugin works on itself before shipping.

#### Required run count by release type

| Release type | Runs required | Representative issues |
|---|---|---|
| `patch` (`x.y.Z → x.y.Z+1`) | **1** | The most representative fix in the release (typically *the* headline fix). In many cases, the release PR itself is the dogfooding run — no extra work needed. |
| `minor` (`x.Y.z → x.Y+1.0`) | **3** | 1 trivial typo, 1 mid-size feature, 1 cross-cutting redesign. |
| `major` (`X.y.z → X+1.0.0`) | **3** | Same 3 categories as minor, **plus** explicit sign-off from CSO and CTO reviewer skills (`/claude-c-suite:cso` and `/claude-c-suite:cto`) captured in the release notes. |

If a required category has no representative issue in the current cycle (e.g. a clean patch with no typos in the backlog), substitute with the next-closest-grain item — a README tweak or comment fix for the typo slot, the largest spec-surface feature for the cross-cutting slot. Document the substitution in the release notes.

#### Evidence bundle schema (minimum)

For each dogfooding run, attach the following to the release notes as a markdown code block or linked release artifact:

```
- state JSON: ~/.claude/cache/gh-issue-driven/<branch-flat>.json
- gate1.md:   ~/.claude/cache/gh-issue-driven/<branch-flat>.gate1.md
- gate2.md:   ~/.claude/cache/gh-issue-driven/<branch-flat>.gate2.md  (if gate2 ran)
- PR URL:     https://github.com/<owner>/<repo>/pull/<N>
```

Variation release-to-release is fine — the point is a consistent minimum that lets a reviewer reconstruct what happened.

#### Pass criterion

A dogfooding run **passes** when:

1. It reaches `phase=done` in the state file (manual confirmation or merged), **or**
2. It reaches `phase=pr_open` and the PR is subsequently merged before the release tag for that release is cut, **or**
3. It stopped at a gate with an explicit maintainer override documented in the release notes ("gate2 yellow: <reason>, proceeding with --force").

A run that aborted at `phase=designed` or `phase=gated` without an override does **not** count — that is a checkbox, not evidence. The `phase` field is set by `/gh-issue-driven:start` and `/gh-issue-driven:ship`; `done` is the terminal value written by manual confirmation or merge, and `pr_open` is the phase after `/ship` creates the PR. See `commands/start.md`, `commands/ship.md`, and `commands/review.md` for the full phase state machine.

#### Dogfooding recovery

If a run aborts mid-flow (gate red, test failure, `silent_no_op`, branch protection block during `/tag`):

- **Do NOT rerun from scratch** after `/gh-issue-driven:tag` steps 7–10 have mutated files. Re-running duplicates CHANGELOG entries, re-bumps manifests, and fails on tag collision. Recover from the point of failure step by step.
- **Do** capture the failure state in the release notes: `Dogfooding run N — aborted at phase X, reason: Y`.
- A failed dogfooding run does **not** automatically block the release. It requires maintainer judgment:
  - **Real regression** → fix the underlying issue, rerun the relevant dogfooding run, and only tag once it passes.
  - **Flaky gate signal** (non-deterministic advisor yellow, transient API error, environmental hiccup) → document the reason and proceed. Gate yellow from an advisor is advisory, not a release blocker.

#### Release steps

Once the dogfooding gate is satisfied, follow **one** of the two paths below.

**Recommended — automated path**: on a clean working tree on `main`, run:

```bash
/gh-issue-driven:tag
```

`/gh-issue-driven:tag` requires a clean tree and performs the version bump (`plugin.json` + `marketplace.json`), CHANGELOG update, commit, tag, push, and GitHub Release creation in one atomic ceremony. Do **not** pre-edit `plugin.json` / `marketplace.json` / `CHANGELOG.md` before running it — `/tag` owns those files and will abort on a dirty tree. After `/tag` finishes, edit the created GitHub Release to paste the dogfooding evidence bundle. `/tag` does **not** attach evidence automatically; evidence attach is tracked as a future enhancement in #43.

**Manual path** (when `/tag` is unavailable or you need a custom ceremony):

1. Bump `version` in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (CI enforces sync).
2. Update `CHANGELOG.md` with the new entry.
3. Commit: `git commit -am "chore: release v<X.Y.Z>"`
4. Tag and push: `git tag v<X.Y.Z> && git push origin main --tags`
5. `gh release create v<X.Y.Z> --generate-notes`, then edit to paste the dogfooding evidence bundle.
6. Marketplace auto-discovers the new version.

## Code of conduct

Be kind. Assume good intent. Smaller, focused PRs ship faster than large ones.
