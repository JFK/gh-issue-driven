---
name: gh-issue-driven-ship
description: "Use when the user asks to run /gh-issue-driven:ship, prepare the current issue branch for a PR, run gate2 review, create a pull request, or save session knowledge."
---

# gh-issue-driven:ship

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:ship`, `/gh-issue-driven:ship`, or `gh-issue-driven ship` as the command arguments.
- Read `../../commands/ship.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace, changing durable user configuration, creating pull requests, pushing branches, or taking destructive git actions.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
