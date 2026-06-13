---
name: gh-issue-driven-config
description: "Use when the user asks to run /gh-issue-driven:config, inspect gh-issue-driven settings, initialize the config template, or print a specific config key."
---

# gh-issue-driven:config

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:config`, `/gh-issue-driven:config`, or `gh-issue-driven config` as the command arguments.
- Read `../../commands/config.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace or changing durable user configuration.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
