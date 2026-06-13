---
name: gh-issue-driven-start
description: "Use when the user asks to run /gh-issue-driven:start, start work on one or more GitHub issues, run gate1 design review, create an issue branch, or prepare implementation."
---

# gh-issue-driven:start

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:start`, `/gh-issue-driven:start`, or `gh-issue-driven start` as the command arguments.
- Read `../../commands/start.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace, changing durable user configuration, creating branches, or taking destructive git actions.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
