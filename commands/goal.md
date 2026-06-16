---
description: "DEPRECATED alias for /gh-issue-driven:objective. The milestone-driving orchestrator was renamed in v0.15.0 to avoid colliding with Claude Code's built-in /goal command. This alias forwards to /gh-issue-driven:objective and will be removed in v0.16.0."
arguments:
  - name: target
    description: "Same arguments as /gh-issue-driven:objective — forwarded verbatim. See that command for the full argument and flag reference."
    required: false
---

# /gh-issue-driven:goal — renamed to `/gh-issue-driven:objective`

> ⚠️ **Deprecated (v0.15.0).** This command was renamed to **`/gh-issue-driven:objective`** to avoid colliding with Claude Code's built-in `/goal` command (which sets a persistent cross-turn goal — a different, conceptually-adjacent feature, easy to confuse in autocomplete and prose). This alias will be **removed in v0.16.0**.

## Behavior

Forward to the renamed command, then stop:

1. Print one line: `note: /gh-issue-driven:goal was renamed to /gh-issue-driven:objective (v0.15.0); forwarding. Update your usage — this alias is removed in v0.16.0.`
2. **Invoke the `/gh-issue-driven:objective` skill via the Skill tool**, passing the operator's arguments (everything that followed `goal`) verbatim as the `target` input.
3. Do not re-implement any milestone logic here — `/gh-issue-driven:objective` is the single source of truth. This file exists only to redirect existing callers during the deprecation window.
