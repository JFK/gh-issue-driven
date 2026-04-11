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

Output language for **operator-facing ephemeral output** — the recap text in `start.md` step 16, the gate prompts shown in the terminal, the AskUserQuestion 文言, the doctor diagnostics, the status pretty-print, and any prose narration Claude produces between steps. Accepts any language identifier (e.g. `"en"`, `"ja"`, `"ko"`, `"de"`). Default `"en"`. Claude translates on the fly using its native multilingual ability — no translation table or message catalog is involved.

The 3-layer policy governs what gets localized:

- **Layer A — Durable artifacts (always English)**: PR title/body, commit messages, branch names, state JSON values. NEVER localized regardless of `lang`.
- **Layer B — Operator-facing ephemeral (configurable)**: this is what `lang` controls. When `lang != "en"`, Claude produces these in the specified language on the fly. The templates in command files stay English — Claude translates them at execution time.
- **Layer C — Parser tokens (always English-strict)**: `## Verdict: green|yellow|red|decline|pass|fail`, `exit_reason` enum values (`silent_no_op`, `no_actionable_feedback`, `approved`, `max_loops`, `tests_failed`, `hitl_declined`), `detection_method` enum values (`requested_reviewers`, `latest_reviews`, `neither`), `hitl_decision` enum string values (`confirmed`, `declined`). NEVER localized — these are parser contract. For `hitl_decision`, the field may also be JSON `null` or absent entirely (backward compat with pre-v0.3.0 state files and gate-disabled runs) — absent/null is NOT a literal enum value, it is the "no value" sentinel that readers treat as "gate was not run".

When `lang != "en"`, gate prompts sent to reviewer skills (`/claude-c-suite:ask`, `/audit`, etc.) get a language hint appended that includes the raw `lang` value for determinism, with a best-effort human-readable name (e.g. `Please respond in Japanese (日本語) (lang: ja).`). The raw value ensures correctness even for BCP-47 tags like `zh-Hans` or `pt-BR` where the human-readable name may be ambiguous. Reviewer responses then naturally produce localized review prose while still emitting the English-strict verdict tokens (the parser contract is documented in the prompt itself, so reviewers know to keep verdict tokens English). This is best-effort — reviewer skills are separate plugins and may occasionally respond in English regardless of the hint.

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

### `review.provider`

Selects which post-PR reviewer to use in ship.md steps 13–14 and the standalone `/gh-issue-driven:review` command. Accepts one of four values:

| Value | Behavior |
|---|---|
| `"copilot"` (default) | GitHub Copilot — async poll-based iterative loop (existing behavior). Uses `copilot.*` config for tuning. |
| `"code-review"` | `/code-review` (official Claude Code plugin) — in-turn single-shot invocation. Posts a PR comment with findings. No polling loop. |
| `"both"` | Runs `/code-review` first (in-turn, single-shot), then Copilot loop (async, iterative). Sequential, not parallel — `/code-review` completes before Copilot starts. |
| `"none"` | Skip post-PR review entirely. Equivalent to the legacy `no-copilot` flag, but config-level. |

**Interaction with `copilot.enabled`**: When the user config explicitly sets `review.provider`, that value controls reviewer selection and `copilot.enabled` is ignored. When `review.provider` is absent from the user config, the legacy `copilot.enabled` field is consulted: if explicitly `false`, `REVIEW_PROVIDER` becomes `"none"`. Otherwise, the built-in default `"copilot"` is used. New users should use `review.provider` instead of `copilot.enabled`.

**Interaction with the `no-copilot` flag**: The `no-copilot` flag on `/gh-issue-driven:ship` overrides `review.provider` to `"none"` for that invocation only. It does not modify the config file.

**`/code-review` requirements**: The `/code-review` plugin must be installed. It requires an existing PR (invoked after step 12). It posts a PR comment rather than a structured verdict — the review command reads the comment and extracts actionable findings. Missing-plugin behavior: both `/gh-issue-driven:ship` and `/gh-issue-driven:review` warn and skip only the `/code-review` portion when it is not installed. If provider is `"code-review"`, the review step exits cleanly with a warning. If provider is `"both"`, Copilot still runs.

**Draft PR compatibility**: `/code-review` works on draft PRs (reads `gh pr diff` directly). Copilot review on a draft PR is not reliable and will typically result in `silent_no_op` rather than a usable review outcome (see memory `85c3fd82`). If you need Copilot review, promote the PR to ready-for-review first. With provider set to `"both"` on a draft PR, `/code-review` can still run even if the Copilot portion does not. When `copilot.hitl_confirm_invocation` is `true` (default, see below), the HITL gate surfaces this caveat in the prompt text when the PR is draft, so the operator can preemptively decline and promote before re-entering via `/gh-issue-driven:review`.

### `copilot.hitl_confirm_invocation`

When `true` (default), `ship.md` step 13c and `review.md` step 5 pause before entering the Copilot polling loop and ask the operator via `AskUserQuestion` whether Copilot review should actually be invoked. The gate has three options: **Yes** (proceed to the loop, records `hitl_decision="confirmed"` and `hitl_confirmed_at=<now>`), **No** (skip the loop cleanly, records `exit_reason="hitl_declined"` and `hitl_decision="declined"`), **Retry** (re-present the prompt immediately — the plugin does not poll between re-emits).

**Why it exists**: the `gh pr edit --add-reviewer @copilot` call is fire-and-forget and cannot be programmatically verified. Real failure modes (org permissions, Copilot billing/policy, Mode A/B toggle, manual comment-mention triggers, draft-PR unreliability) are not API-queryable. Instead of growing a detection matrix, the plugin asks the operator — who can see the PR — to confirm.

**Skip conditions**: the gate is silently bypassed when `DRY_RUN` is set, when `REVIEW_PROVIDER` is not `copilot` or `both`, or when the prior state already has `review.copilot.hitl_confirmed_at` set (re-entry from a prior `/ship` or `/review` invocation that already confirmed — prevents double-prompting on resume).

**`silent_no_op` semantics** change with this gate: before v0.3.0, `silent_no_op` meant "Copilot was never detected — cause unknown". After v0.3.0, `silent_no_op` means "operator confirmed invocation (or gate was disabled) AND Copilot still did not respond" — a real anomaly signal. The decline path uses `hitl_declined` as a separate, intentional terminal state.

**Set to `false`** to restore the pre-v0.3.0 behavior exactly (no prompt, no `hitl_*` fields in state). Useful for CI or non-interactive environments where the operator cannot respond to AskUserQuestion.

### `memory.context_id`

Accepts three forms — in priority order of recommendation:

| Form | Example | Meaning |
|---|---|---|
| `null` (default) | `"context_id": null` | Auto-detect on first run per repo (see step 2b). |
| **object** (dict) | `{"JFK/gh-issue-driven": "4b080ca8-…", "*": "abfd654d-…"}` | **Recommended.** Per-repo mapping. Keys are `owner/repo` strings matched against the repo running `/start`. Values are UUIDs or context names. The special key `"*"` is a wildcard fallback used when no exact key matches. |
| string (UUID or name) | `"context_id": "4b080ca8-…"` | **Legacy scalar.** Same context for all repos. Still works, but will be auto-upgraded to the dict form on next auto-detect. |

**Why dict form is recommended**: each repo typically wants its own Kagura Memory context (project-specific knowledge, decisions, patterns). With the scalar form, every repo shared the same context, mixing unrelated concerns. The dict form lets you bind one context per repo and keep them cleanly separated, while still supporting a catch-all via `"*"`.

**Lookup order at `/start` time** (see start.md step 2a):

1. If `null`/missing → auto-detect (step 2b) → persists to `context_id[<this repo>]`.
2. If dict → look up exact `REPO_FULL_NAME` key → if miss, look up `"*"` key → if both miss, auto-detect for this repo (persists to `context_id[<this repo>]`, leaving other entries untouched).
3. If scalar string → use as-is (single-value path). A one-line deprecation note is logged; the next auto-detect will upgrade it in place.

After resolution, the value (either a direct UUID or a name) is further resolved via the UUID/name path:
- **UUID**: used as-is, no lookup.
- **Name**: resolved to a UUID at runtime via `mcp__kagura-memory__list_contexts` (case-insensitive exact match on `.name`).

**Auto-detect (first-run, per repo)**: When the lookup ends in "auto-detect for this repo", `/gh-issue-driven:start` step 2b prompts the user to select an existing context or create a new one. The chosen UUID is then **persisted to this config file** at `context_id[<this repo>]` so the prompt only fires once per repo. The write is scoped to this repo's entry — other entries in the dict (or the existing scalar, if any) are left untouched, except for the one-time scalar → dict auto-upgrade described next.

**Scalar → dict auto-upgrade**: When auto-detect fires with an existing scalar `context_id`, the persist step rewrites it as `{<this repo>: <chosen>, "*": <old_scalar>}`. The old scalar is preserved as the `"*"` wildcard so existing bindings for other repos still resolve — if you don't want the catch-all, remove `"*"` manually afterwards. This is the only path that mutates pre-existing user values; all other auto-detect writes only add a new key.

**Name resolution caveat**: Name values in the dict (or in the legacy scalar form) are resolved fresh each invocation. The resolved UUID is cached **in-session only** — not written back to the config file — keeping the config portable across machines where the same name may resolve to different UUIDs.

**Backward compatibility**: The pre-v0.2.0 default was `"gh-issue-driven-dev"` (a placeholder name, scalar form). If this exact string is present and name resolution fails (no such context exists), `/start` treats it as an auto-detect trigger — the user is prompted to select a context and the scalar auto-upgrade path persists both the chosen UUID and the placeholder as `"*"` fallback. In practice users upgrading from v0.1.x can ignore the migration — the first `/start` after upgrade does the right thing.

**Resolution failure paths** (dict key miss + no wildcard + auto-detect skipped, name not found for non-placeholder names, multiple matches, `list_contexts` errors, kagura-memory not installed) all set the in-session value to `null` and **skip recall without aborting `/start`**. Each failure path logs a single one-line warning. `memory.skip_on_failure` does NOT control these paths — it controls step 7's behavior when the **recall call itself** fails at runtime.

`memory.skip_on_failure` controls the behavior when the recall call errors at runtime (the resolved UUID was valid, the network or server failed mid-call):
- `true` (default): log the error and continue with empty recall results — `/start` proceeds normally
- `false`: abort `/start` with the recall error — for users who treat broken memory as a hard failure

Users without kagura-memory installed can ignore this field — recall is skipped automatically when the plugin is missing.

**Multi-match disambiguation**: if two or more contexts share the same case-insensitive name, resolution sets the in-session value to `null` and skips recall (logging an "ambiguous context" warning). To resolve: set the entry to the exact UUID of the context you want.

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
    "context_id": null,
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
  "review": {
    "provider": "copilot"
  },
  "copilot": {
    "enabled": true,
    "reviewer_login": "@copilot",
    "max_loops": 5,
    "poll_interval_sec": 60,
    "max_wait_sec": 900,
    "silent_no_op_threshold_polls": 3,
    "run_tests_after_edits": true,
    "reply_to_non_actionable": false,
    "skip_setup_prompt": false,
    "hitl_confirm_invocation": true
  },
  "pr": {
    "draft_default": true,
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
