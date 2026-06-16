---
name: gh-issue-driven-objective
description: "Use when the user asks to run /gh-issue-driven:objective, finish a GitHub milestone, or drive multiple milestone issues through start, implementation, ship, and review."
---

# gh-issue-driven:objective

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:objective`, `/gh-issue-driven:objective`, or `gh-issue-driven objective` as the command arguments.
- Read `../../commands/objective.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace, changing durable user configuration, or taking destructive git actions.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
