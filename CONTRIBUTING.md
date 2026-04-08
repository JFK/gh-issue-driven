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

1. Bump `version` in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (CI enforces sync).
2. Update CHANGELOG (when one exists).
3. `git tag vX.Y.Z && git push origin main --tags`
4. Draft a GitHub Release pointing at the new tag.
5. Marketplace auto-discovers the new version.

## Code of conduct

Be kind. Assume good intent. Smaller, focused PRs ship faster than large ones.
