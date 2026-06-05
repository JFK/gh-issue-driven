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

Selects which post-PR reviewer to use in review.md step 5 and the standalone `/gh-issue-driven:review` command. Default is `"none"` — review is opt-in; nothing runs unless you set a provider. Accepts one of four values:

| Value | Behavior |
|---|---|
| `"none"` (default) | Skip post-PR review entirely. Equivalent to the legacy `no-copilot` flag, but config-level. |
| `"copilot"` | GitHub Copilot — async poll-based iterative loop (existing behavior). Uses `copilot.*` config for tuning. |
| `"code-review"` | `/code-review` (official Claude Code plugin) — in-turn single-shot invocation. Posts a PR comment with findings. No polling loop. |
| `"both"` | Runs `/code-review` first (in-turn, single-shot), then Copilot loop (async, iterative). Sequential, not parallel — `/code-review` completes before Copilot starts. |

**Deprecated: `copilot.enabled`** — no longer consulted. Previously, when `review.provider` was absent, `copilot.enabled=false` forced `none`. As of this version the default is `none` regardless, and `copilot.enabled` is ignored. Migrate by setting `review.provider` explicitly (`"copilot"` restores the old auto-review behavior).

### `review.model`

Default `"auto"`. One of `auto | haiku | sonnet | opus` (or a full model id). Tier for the **fix-application subagent** that `/gh-issue-driven:review` dispatches to apply review findings. `auto` right-sizes by the PR's diff scope/risk (docs-only → haiku, normal → sonnet, risky/wide → opus). Does not affect provider selection, the gate2 cascade, or `/code-review`.

**Interaction with the `no-copilot` flag**: The `no-copilot` flag on `/gh-issue-driven:ship` overrides `review.provider` to `"none"` for that invocation only. It does not modify the config file.

**`/code-review` requirements**: The `/code-review` plugin must be installed. It requires an existing PR (invoked after step 12). It posts a PR comment rather than a structured verdict — the review command reads the comment and extracts actionable findings. Missing-plugin behavior: both `/gh-issue-driven:ship` and `/gh-issue-driven:review` warn and skip only the `/code-review` portion when it is not installed. If provider is `"code-review"`, the review step exits cleanly with a warning. If provider is `"both"`, Copilot still runs.

**Draft PR compatibility**: `/code-review` works on draft PRs (reads `gh pr diff` directly). Copilot review on a draft PR is not reliable and will typically result in `silent_no_op` rather than a usable review outcome (see memory `85c3fd82`). If you need Copilot review, promote the PR to ready-for-review first. With provider set to `"both"` on a draft PR, `/code-review` can still run even if the Copilot portion does not. When `copilot.hitl_confirm_invocation` is `true` (default, see below), the HITL gate surfaces this caveat in the prompt text when the PR is draft, so the operator can preemptively decline and promote before re-entering via `/gh-issue-driven:review`.

### `copilot.hitl_confirm_invocation`

When `true` (default), `review.md` step 5a pauses before entering the Copilot polling loop and asks the operator via `AskUserQuestion` whether Copilot review should actually be invoked. The gate has three options: **Yes** (proceed to the loop, records `hitl_decision="confirmed"` and `hitl_confirmed_at=<now>`), **No** (skip the loop cleanly, records `exit_reason="hitl_declined"` and `hitl_decision="declined"`), **Retry** (re-present the prompt immediately — the plugin does not poll between re-emits).

**Why it exists**: the `gh pr edit --add-reviewer @copilot` call is fire-and-forget and cannot be programmatically verified. Real failure modes (org permissions, Copilot billing/policy, Mode A/B toggle, manual comment-mention triggers, draft-PR unreliability) are not API-queryable. Instead of growing a detection matrix, the plugin asks the operator — who can see the PR — to confirm.

**Skip conditions**: the gate is silently bypassed when `DRY_RUN` is set, when `REVIEW_PROVIDER` is not `copilot` or `both`, or when the prior state already has `review.copilot.hitl_confirmed_at` set (re-entry from a prior `/ship` or `/review` invocation that already confirmed — prevents double-prompting on resume).

**`silent_no_op` semantics** change with this gate: before v0.3.0, `silent_no_op` meant "Copilot was never detected — cause unknown". After v0.3.0, `silent_no_op` means "operator confirmed invocation (or gate was disabled) AND Copilot still did not respond" — a real anomaly signal. The decline path uses `hitl_declined` as a separate, intentional terminal state.

**Set to `false`** to restore the pre-v0.3.0 behavior exactly (no prompt, no `hitl_*` fields in state). Useful for CI or non-interactive environments where the operator cannot respond to AskUserQuestion.

### `copilot.reply_to_threads` / `copilot.resolve_threads`

Control what the Copilot review loop (`review.md` step 5b) does with individual inline review threads after it has applied fixes and pushed.

When **`reply_to_threads`** is `true` (default), the loop posts an in-thread reply to each Copilot review thread it processed:

- **actionable** threads (a code change was actually made) get a reply citing the fix commit: `✅ Fixed in <short-sha>: <summary>`.
- **non-actionable** threads (style nits, questions, disagreements) get a reply stating the rationale for not changing code.

When **`resolve_threads`** is `true` (default), the loop additionally **resolves actionable threads only** (via the GitHub GraphQL `resolveReviewThread` mutation — there is no REST endpoint for this). Non-actionable threads are deliberately **left open** so the reviewer can follow up.

**Implementation notes**: thread IDs come from a GraphQL `pullRequest.reviewThreads` query (the polling JSON in review.md step 5b does not include inline threads). All reply/resolve calls are **best-effort** — a failure (e.g. insufficient permissions on a fork PR) logs a warning but never aborts the loop, since the fix itself is already pushed. Both behaviors are skipped entirely under `DRY_RUN`. Counts are recorded in state as `review.copilot.threads_replied` / `threads_resolved` and surfaced by `/gh-issue-driven:status`.

**Set `reply_to_threads` to `false`** to restore the legacy behavior (no per-thread replies; the loop just re-requests review). **Set `resolve_threads` to `false`** to reply without resolving (leave all threads for the reviewer to close).

### `copilot.reply_to_non_actionable` (deprecated)

When `true`, the loop posts a single PR-level summary comment listing skipped (non-actionable) suggestions. **Superseded by `reply_to_threads`**, which replies to each thread individually. Defaults to `false` and is retained only for backward compatibility; new configs should rely on `reply_to_threads` instead.

### `doctor.expected_origins`

Object mapping plugin skill names to their expected canonical HTTPS repository URLs. When set, `doctor` reads each installed plugin's `plugin.json` from the cache and compares its `repository` field against the configured value. A mismatch emits a `⚠️  <skill>: origin mismatch: ...` line — a supply-chain hygiene check that catches a plugin being silently replaced by a fork or a same-name impersonator.

**Default** maps the four plugins gh-issue-driven depends on to their canonical origins:

```json
{
  "claude-c-suite":   "https://github.com/JFK/claude-c-suite-plugin",
  "claude-phd-panel": "https://github.com/JFK/claude-phd-panel-plugin",
  "kagura-memory":    "https://github.com/kagura-ai/memory-cloud",
  "feature-dev":      null
}
```

Set a key to `null` to skip the origin check for that plugin (any origin is accepted). `feature-dev` defaults to `null` because official Anthropic plugins carry no `repository` field in their `plugin.json`.

To trust a fork, change the URL: `"claude-c-suite": "https://github.com/yourfork/claude-c-suite-plugin"`. Comparison is case-sensitive exact string match — write the URL exactly as it appears in the plugin's own `plugin.json` (no trailing slash, HTTPS, no `.git` suffix).

**CI use**: run `doctor verbose` and `grep '^PLUGIN_CHECK'` to parse machine-readable `key=value` lines. Fail on `status=unexpected` to enforce origin pinning in CI.

### `gate1.size_heuristic`

Opt-in mechanism that lets `/gh-issue-driven:start` skip the gate1 cascade entirely for issues that match a "small issue" heuristic. Default is **off** for backward compatibility — when disabled, `/start` runs gate1 (`/claude-c-suite:ask` → optional `/ceo` escalation) on every issue, exactly as in v0.8.0.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Master switch. When `true`, the heuristic runs in `/start` step 7a. The CLI flag `auto-size` is the per-invocation equivalent. |
| `small_labels` | `["good first issue", "documentation", "docs", "tests", "i18n"]` | Case-insensitive label list. If the primary issue has any label in this list, the issue is small. |
| `small_body_max_chars` | `500` | If the primary issue body is shorter than this, the issue is small. |

**Trigger logic**: an issue is small when **either** signal fires — label match OR short body. Both proxies capture the same "implementer can act without design review" intuition; the OR captures both labeled triage signals and short-body brevity signals.

**Effect when small**: gate1 (`/claude-c-suite:ask`, optional `/ceo` escalation) is **not** invoked. `GATE1_REVIEWER` is set to the sentinel `"size-heuristic"`, `GATE1_VERDICT` to `green`, and the gate1 markdown captures a synthetic "skipped by policy" record. The HITL gate (`gate1.green_continue_requires_confirm`) still fires so the operator can override the size-heuristic decision by selecting "I have feedback".

**Batch mode**: `IS_BATCH=true` invocations are **never** small. Bundling multiple issues is itself a coherence signal that warrants gate1 review.

**Token savings**: the saved cost is one `/claude-c-suite:ask` invocation per matching issue (plus the rarer `/ceo` escalation when the verdict is decline). For a docs-only typo fix, this is the dominant cost in `/start` — order-of-magnitude reduction is realistic.

### `gate2.diff_scope_skip`

Opt-in mechanism that lets `/gh-issue-driven:ship` skip irrelevant gate2 advisors based on the changed-file scope. Default is **off** for backward compatibility — when disabled, `/ship` runs every advisor in `gate2.advisors`, exactly as in v0.8.0.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Master switch. When `true`, ship.md step 4a probes the diff and may filter `ADVISORS`. The CLI flag `auto-skip` is the per-invocation equivalent. |
| `docs_only_patterns` | `["^README", "^CHANGELOG", "^CONTRIBUTING", "^docs/", "^\\.github/"]` | Regex list. A diff is **docs-only** when **every** changed file matches at least one pattern. |
| `docs_only_skip_advisors` | `["/claude-c-suite:cso", "/claude-c-suite:qa-lead"]` | Advisors skipped when the diff is docs-only. The remaining advisors (e.g. `cto`) still run. |

**Important**: this plugin's `commands/*.md` files are markdown-as-code (the runtime spec) — they are intentionally **not** in the default `docs_only_patterns`. Editing `commands/start.md` is a behavioral change, not docs. If you customize the patterns, keep this invariant.

**Effect when docs-only**: the matched advisors are excluded from the parallel battery in ship.md step 6. The binary gate (`gate2.binary_gate`) is never affected — it has its own opt-in via the `binary_gate` key. `SKIPPED_ADVISORS` is recorded in the gate2 state block (`gate2.skipped_advisors`) so `/gh-issue-driven:status` can surface what was skipped and why.

**When NOT to enable**: if your repo treats `docs/` as security-sensitive (e.g. published threat models, secret-management docs that could leak credentials when edited), keep the default `false`. Skipping `cso` is appropriate only when docs changes carry no security review obligation.

### `goal.*`

Tuning for `/gh-issue-driven:goal`, the autonomous milestone-completion loop.

| Key | Default | Meaning |
|---|---|---|
| `autonomy` | `"red-only"` | Verdict-gating policy. `"red-only"`: treat `green`/`yellow` as continue (yellow auto-accepted and logged), gate for HITL **only** on a `red` gate1/gate2 verdict. `"unattended"`: red is also auto-accepted (the `force` flag forces this for one run); safety caps are the only backstop. `"attended"`: gate on green/yellow too. `/goal` forwards this value verbatim to the delegated `/start` and `/ship` as `--autonomous=<level>` (#74): under `red-only`/`unattended` they suppress their own green/yellow + Copilot-invocation prompts (and on `red` without `force` persist the verdict and return control rather than aborting); under `attended` suppression is disabled and the sub-commands' own prompts fire as normal. |
| `max_issues_per_run` | `20` | Runaway backstop. Issues beyond the cap are deferred (logged loudly, never silently dropped) — re-run with `resume` to continue. |
| `inner_review.enabled` | `true` | Whether step 5b runs a **cheap inner-review pass** over the working-tree diff before handing off to `/ship`'s heavy gate2 cascade. When `false`, 5b falls back to `/code-review` at a size-scaled effort level (the pre-#76 behavior). |
| `inner_review.model` | `"auto"` | Model tier for the inner-review subagent. `auto` (default) right-sizes by working-tree diff scope (docs→haiku, normal→sonnet, risky→opus); a fixed alias (`haiku`/`sonnet`/`opus`/id) is used verbatim. The cheap tier keeps the *inner* loop inexpensive; the authoritative review stays the gate2 cascade. Implementation runs on the normal session model regardless. |
| `inner_review.max_rounds` | `2` | Cap on the cheap fix-and-recheck loop (the inner review is a fast filter, not the authoritative gate). Findings beyond the cap are left for gate2 to catch. |

The autonomy level governs **verdict** gating only. The milestone-missing precondition and any non-verdict abort from a delegated command always stop the run regardless of level. `/goal` **delegates the PR + Copilot review loop to `/ship`** (it does not run its own loop); that loop uses `copilot.*` (poll interval, max wait, silent-no-op threshold, `max_loops`) and `review.provider` for reviewer selection, exactly as a direct `/ship` run does.

**Controlling review cost.** Because `/goal` fans the review machinery across *every* open issue in a milestone, the Copilot loop is the dominant cost. Two independent levers, neither adding a new `goal.*` key:
- **PR review (the expensive async Copilot loop)** — optional via the inherited `review.provider`: set it to `"none"` (no automated PR review) or `"code-review"` (single-shot, no polling loop) for a persistent, cheaper default; or pass the per-run `no-copilot` flag to `/gh-issue-driven:goal`, which forwards to `/ship` as `no-copilot` for that run only. With Copilot off, each issue's PR is opened and left for manual review (recorded `needs_human`).
- **Inner review (the cheap pre-PR pass)** — `goal.inner_review.model` (default `"auto"`) right-sizes by diff scope; the `review-model=<tier>` flag re-tiers it per run, and `goal.inner_review.enabled=false` removes it entirely (falling back to `/code-review`). Implementation always runs on the normal session model — only the review subagent is downshifted.

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
    "yellow_continue_requires_confirm": true,
    "green_continue_requires_confirm": true,
    "size_heuristic": {
      "enabled": false,
      "small_labels": ["good first issue", "documentation", "docs", "tests", "i18n"],
      "small_body_max_chars": 500
    }
  },
  "gate2": {
    "binary_gate": null,
    "advisors": [
      "/claude-c-suite:cso",
      "/claude-c-suite:qa-lead",
      "/claude-c-suite:cto"
    ],
    "yellow_continue_requires_confirm": true,
    "green_continue_requires_confirm": true,
    "run_tests_before_gate2": false,
    "diff_scope_skip": {
      "enabled": false,
      "docs_only_patterns": ["^README", "^CHANGELOG", "^CONTRIBUTING", "^docs/", "^\\.github/"],
      "docs_only_skip_advisors": ["/claude-c-suite:cso", "/claude-c-suite:qa-lead"]
    }
  },
  "review": {
    "provider": "none",
    "model": "auto"
  },
  "copilot": {
    "enabled": true,
    "reviewer_login": "@copilot",
    "max_loops": 5,
    "poll_interval_sec": 60,
    "max_wait_sec": 900,
    "silent_no_op_threshold_polls": 3,
    "run_tests_after_edits": true,
    "reply_to_threads": true,
    "resolve_threads": true,
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
  "dry_run_env_var": "GH_ISSUE_DRY_RUN",
  "propose": {
    "reviewer": "/claude-c-suite:ask",
    "pm_skill": "/claude-c-suite:pm",
    "dedup_max_results": 10,
    "yellow_continue_requires_confirm": true
  },
  "goal": {
    "autonomy": "red-only",
    "max_issues_per_run": 20,
    "inner_review": {
      "enabled": true,
      "model": "auto",
      "max_rounds": 2
    }
  },
  "doctor": {
    "expected_origins": {
      "claude-c-suite":   "https://github.com/JFK/claude-c-suite-plugin",
      "claude-phd-panel": "https://github.com/JFK/claude-phd-panel-plugin",
      "kagura-memory":    "https://github.com/kagura-ai/memory-cloud",
      "feature-dev":      null
    }
  }
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
