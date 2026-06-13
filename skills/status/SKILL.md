---
name: gh-issue-driven-status
description: "Use when the user asks to run /gh-issue-driven:status, inspect gh-issue-driven state for the current branch, check gate verdicts, PR status, or Copilot loop progress."
---

# gh-issue-driven:status

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:status`, `/gh-issue-driven:status`, or `gh-issue-driven status` as the command arguments.
- Read `../../commands/status.md` and follow it as the source of truth.
- Preserve the command's trust boundary. This command is read-only unless the referenced source command explicitly says otherwise.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
