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

### `memory.context_id`

Accepts **either** a Kagura Memory context UUID (e.g. `4b080ca8-4f2b-4506-9b55-77590b1423cb`) **or** a context **name** (e.g. `gh-issue-driven-dev`). When a name is given, `/gh-issue-driven:start` resolves it to a UUID at runtime via `mcp__kagura-memory__list_contexts` (see start.md step 2a). The resolution happens fresh on every invocation; the resolved UUID is **not** written back to this config file, keeping it portable across machines and Kagura Memory installations.

If the name is not found in the user's Kagura Memory contexts, recall is skipped silently for that session (log line emitted) — the rest of `/start` continues normally. Set `memory.skip_on_failure=false` to make recall failure abort the command instead.

The default `gh-issue-driven-dev` is a placeholder. Users with kagura-memory installed should change it to either:
- The UUID of their preferred context, OR
- The exact name of an existing context in their Kagura Memory

Users without kagura-memory installed can ignore this field — recall is skipped automatically when the plugin is missing.

## Built-in defaults

```json
{
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
    "binary_gate": "/claude-c-suite:audit",
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
