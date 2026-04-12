## For pull request reviews

### What this project is

A Claude Code plugin — all "code" is Markdown instruction files (`commands/*.md`) that an LLM interprets at runtime. There is no compiled code, no runtime dependencies beyond `gh`/`git`/`jq`/`python3`, and no package manager lockfiles.

### Priority

- Report only high-signal issues: logic gaps where Claude could misinterpret the step sequence, missing edge cases in verdict parsing or state file handling, security boundary violations (shell injection, path traversal, secret leakage), and broken cross-references between commands.
- Skip pure formatting or style suggestions — Markdown formatting is intentional and serves as LLM instruction structure.
- Do NOT flag the length of command files. They are long by design — each command is a self-contained instruction set.

### Consolidation

- Group similar findings into one comment with all locations listed.
- If more than 5 issues found, report only the top 5 by severity. Mention the count of lower-priority items in a summary line.

### Project conventions

- Command files follow a strict structure: YAML frontmatter, `## Output language`, `## Trust boundary`, `## Steps` (numbered), `## Failure modes` table, advisory footer.
- The 3-layer localization policy: Layer A (durable artifacts — always English), Layer B (operator-facing — configurable via `lang`), Layer C (parser tokens like `## Verdict: green|yellow|red` — always English).
- `## Verdict:` lines are parser contract — do not suggest changing their format.
- State files at `~/.claude/cache/gh-issue-driven/` use atomic temp+mv writes.
- AskUserQuestion always uses fixed options (no free-form input).
- Config keys use `snake_case` and are deep-merged over built-in defaults from `config.md`.
- Version sync between `plugin.json` and `marketplace.json` is CI-enforced.

### What NOT to flag

- Inline bash blocks in Markdown — these are instruction templates, not literal shell scripts. Claude substitutes `<PLACEHOLDER>` values before execution.
- `<user_data>` tags wrapping external content — this is the plugin's prompt injection defense pattern.
- Cross-file references like "same algorithm as `start.md` step 8a" — these are intentional DRY references for LLM instruction reuse.
- Long step descriptions — LLMs need explicit, unambiguous instructions.
