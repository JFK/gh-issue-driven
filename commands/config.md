---
description: Show the effective gh-issue-driven configuration, or stamp a fresh annotated template at ~/.claude/gh-issue-driven-config.json (only if absent — never overwrites).
arguments:
  - name: action
    description: "Optional: 'show' (default — pretty-print effective config), 'init' (stamp template if file is missing), 'path' (print absolute config file path), or '<dotted.key>' (print one effective value, e.g. 'copilot.max_loops')."
    required: false
---

## Trust boundary

This command is **mostly read-only**. The single mutating action is `init`, which writes `~/.claude/gh-issue-driven-config.json` only when the file does not yet exist. It must NEVER overwrite an existing config file. Never echo unrelated files. Never modify anything outside `~/.claude/gh-issue-driven-config.json`.

## Notes on specific keys

### `lang`

Output language for **operator-facing ephemeral output** — the recap text in `start.md` step 16, the gate prompts shown in the terminal, the AskUserQuestion 文言, the doctor diagnostics, the status pretty-print, and any prose narration Claude produces between steps. Accepts `"en"` (default) or `"ja"`.

This is a minimal v0.1.1 implementation (Option A from the dogfooding session for #15). The full 3-layer i18n policy is tracked as #19 (v0.1.2). The minimal implementation honors the same 3-layer policy at low cost:

- **Layer A — Durable artifacts (always English)**: PR title/body, commit messages, branch names, state JSON values. NEVER localized regardless of `lang`.
- **Layer B — Operator-facing ephemeral (configurable)**: this is what `lang` controls. When `lang == "ja"`, Claude produces these in Japanese on the fly using its native multilingual ability. The templates in command files stay English — Claude translates them at execution time.
- **Layer C — Parser tokens (always English-strict)**: `## Verdict: green|yellow|red|decline|pass|fail`, `exit_reason` enum values (`silent_no_op`, `no_actionable_feedback`, `approved`, `max_loops`, `tests_failed`), `detection_method` enum values (`requested_reviewers`, `latest_reviews`, `neither`). NEVER localized — these are parser contract.

When `lang == "ja"`, gate prompts sent to reviewer skills (`/claude-c-suite:ask`, `/audit`, etc.) get a final line `Please respond in Japanese.` appended. Reviewer responses then naturally produce Japanese review prose while still emitting the English-strict verdict tokens (the parser contract is documented in the prompt itself, so reviewers know to keep verdict tokens English).

What v0.1.1 minimal does NOT do (left for v0.1.2 / #19): no translation table, no message catalog, no CI parity lint, no source-level localization of templates. The English templates in command files remain visible to anyone reading the spec; only the runtime output is localized.

### `gate2.binary_gate`

Optional skill name that gate2 invokes as a **binary release gate** (returns `pass` or `fail`, with `fail` being a hard release block that even `--force` cannot override). The default is `null`, which means **gate2 runs in advisor-only mode** — only the 3 advisors (`cso`, `qa-lead`, `cto`) are invoked, and their aggregate verdict (green/yellow/red) is the sole gate2 signal.

**Why the default is `null`** (changed in v0.1.1 from `/claude-c-suite:audit`):

The previous default `/claude-c-suite:audit` is the conformance audit script for the `claude-c-suite` plugin's own command files. It runs `python3 scripts/audit.py`, and that script exists ONLY in the `claude-c-suite-plugin` repo. For any other plugin (gh-issue-driven, kagura-memory, claude-phd-panel, etc.), the script doesn't exist, so `/audit` errors out, and ship.md's "binary gate unavailable → require --force" rule blocked every `/ship` invocation in non-claude-c-suite-plugin repos. That was a real new-user blocker. The fix: make the binary gate opt-in.

**Setting `binary_gate` to a non-null skill name**:

If you maintain `claude-c-suite-plugin` itself, set `gate2.binary_gate: "/claude-c-suite:audit"` to enable the conformance check. The skill is then invoked as part of the gate2 parallel reviewer battery (alongside the 3 advisors), and its verdict is read as a hard binary gate per ship.md step 7. Any other skill name can also be set if a generic audit skill is added in the future — the contract is just "the skill must emit a `## Verdict: pass` or `## Verdict: fail` line."

**What advisor-only mode means in practice**:

- ship.md step 6 invokes only 3 reviewers (cso, qa-lead, cto)
- ship.md step 7 (audit verdict) is skipped entirely; `AUDIT_VERDICT = "skipped"`
- ship.md step 8 (advisor aggregation) computes the gate2 verdict from the 3 advisors
- ship.md step 9 (verdict handling) reads green/yellow/red as the sole signal — no separate "binary gate failed" abort path
- ship.md step 12 PR body shows `gate2 mode: advisor-only (no binary gate configured)` instead of `audit: pass`

In advisor-only mode, the 3-advisor aggregate is the gate2 signal. All three returning green proceeds; any yellow asks for confirmation; any red aborts unless `--force` is set.

### `memory.context_id`

Accepts **either** a Kagura Memory context UUID (e.g. `4b080ca8-4f2b-4506-9b55-77590b1423cb`) **or** a context **name** (e.g. `gh-issue-driven-dev`). Name matching is **case-insensitive** (so `Gh-Issue-Driven-Dev` and `gh-issue-driven-dev` both resolve to the same context). When a name is given, `/gh-issue-driven:start` resolves it to a UUID at runtime via `mcp__kagura-memory__list_contexts` (see start.md step 2a). The resolution happens fresh on every invocation; the resolved UUID is **not** written back to this config file, keeping it portable across machines and Kagura Memory installations.

**Resolution failure paths** (name not found / multiple matches / list_contexts errors / kagura-memory not installed) all set the in-session value to `null` and **skip recall without aborting `/start`**. Each failure path logs a single one-line warning so the operator knows recall was skipped and why; "skip" means "do not abort the command", not "do not log." `memory.skip_on_failure` does NOT control these paths because they happen *before* the recall call. The rationale: a config that can't even produce a UUID is not "kagura-memory failed at runtime," it's "you don't have a usable memory setup yet" — fail-safe is the right call.

`memory.skip_on_failure` controls the behavior when the **recall call itself** errors at runtime (the resolved UUID was valid, the network or server failed mid-call):
- `true` (default): log the error and continue with empty recall results — `/start` proceeds normally
- `false`: abort `/start` with the recall error — for users who treat broken memory as a hard failure

The default `gh-issue-driven-dev` is a placeholder. Users with kagura-memory installed should change it to either:
- The UUID of their preferred context, OR
- The exact name of an existing context in their Kagura Memory (case-insensitive match)

Users without kagura-memory installed can ignore this field — recall is skipped automatically when the plugin is missing.

**Multi-match disambiguation**: if two or more contexts share the same case-insensitive name, resolution sets the in-session value to `null` and skips recall (logging an "ambiguous context" warning). To resolve: set `memory.context_id` to the exact UUID of the context you want.

## Built-in defaults

```json
{
  "lang": "en",
  "default_branch": "main",
  "branch": {
    "type_label_map": {
      "bug": "fix",
      "fix": "fix",
      "feature": "feat",
      "enhancement": "feat",
      "refactor": "refactor",
      "test": "test",
      "documentation": "docs",
      "docs": "docs"
    },
    "default_type": "feat",
    "max_slug_chars": 40
  },
  "memory": {
    "context_id": "gh-issue-driven-dev",
    "recall_k": 5,
    "skip_on_failure": true
  },
  "gate1": {
    "primary": "/claude-c-suite:ask",
    "fallback": "/claude-c-suite:ceo",
    "yellow_continue_requires_confirm": true
  },
  "gate2": {
    "binary_gate": null,
    "advisors": [
      "/claude-c-suite:cso",
      "/claude-c-suite:qa-lead",
      "/claude-c-suite:cto"
    ],
    "yellow_continue_requires_confirm": true,
    "run_tests_before_gate2": false
  },
  "copilot": {
    "enabled": true,
    "reviewer_login": "@copilot",
    "max_loops": 5,
    "poll_interval_sec": 60,
    "max_wait_sec": 900,
    "run_tests_after_edits": true,
    "reply_to_non_actionable": false,
    "verification_wait_sec": 30,
    "skip_setup_prompt": false
  },
  "pr": {
    "draft_default": false,
    "title_template": "{type}: {title} (#{number})"
  },
  "tag": {
    "label_group_map": {
      "bug": "Bug Fixes",
      "enhancement": "Enhancements",
      "documentation": "Documentation",
      "security": "Security",
      "tech-debt": "Tech Debt",
      "tests": "Testing",
      "i18n": "Internationalization"
    },
    "default_group": "Other",
    "auto_close_milestone": false
  },
  "dry_run_env_var": "GH_ISSUE_DRY_RUN"
}
```

## Steps

Parse `$ARGUMENTS` into one of: `show` (default), `init`, `path`, or a dotted key path like `copilot.max_loops`.

### Action: `show` (default)

1. Define `CONFIG=~/.claude/gh-issue-driven-config.json`.
2. If `CONFIG` exists, parse it with `jq`. On parse error, print the error and fall back to an empty user config.
3. Deep-merge user values over the built-in defaults (the user wins on any key it sets).
4. Print the merged config as pretty JSON.
5. Beneath the JSON, print a one-line origin annotation for top-level keys: `default_branch: user`, `gate1.primary: default`, etc. — only show keys whose origin is `user` (so the user can quickly see what they have customized).

### Action: `init`

1. If `~/.claude/gh-issue-driven-config.json` already exists, print:
   ```
   config exists at ~/.claude/gh-issue-driven-config.json
   will not overwrite — edit it manually if you need changes
   ```
   Exit. Do not modify anything.
2. If absent, write the built-in defaults (the JSON block above) to a temp file, then atomically move:
   ```bash
   mkdir -p ~/.claude
   tmp=$(mktemp)
   cat > "$tmp" <<'EOF'
   { ... defaults ... }
   EOF
   jq empty "$tmp" || { echo "internal error: defaults JSON invalid"; rm -f "$tmp"; exit 1; }
   mv "$tmp" ~/.claude/gh-issue-driven-config.json
   chmod 0644 ~/.claude/gh-issue-driven-config.json
   ```
3. Print: `wrote ~/.claude/gh-issue-driven-config.json`.

### Action: `path`

Print `~/.claude/gh-issue-driven-config.json` (absolute path expansion: `$HOME/.claude/gh-issue-driven-config.json`). Indicate whether the file currently exists or not.

### Action: `<dotted.key>`

If `$ARGUMENTS` is a non-empty string that doesn't match `show`, `init`, or `path`, treat it as a dotted JSON path. Use `jq` to read it from the merged effective config:

```bash
jq -r ".$ARGUMENTS" <(merged-effective-config-json)
```

If the key doesn't exist, print `null` and exit non-zero. If the key exists, print only the value (no quotes for strings, raw JSON for objects/arrays).

---

> ⚠️ **Mostly read-only**: Only `init` writes a file, and only if the file doesn't already exist. Never overwrites.
