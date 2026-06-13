---
name: gh-issue-driven-propose
description: "Use when the user asks to run /gh-issue-driven:propose, turn session context into a GitHub issue, deduplicate issue ideas, or create an issue through the gh-issue-driven workflow."
---

# gh-issue-driven:propose

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:propose`, `/gh-issue-driven:propose`, or `gh-issue-driven propose` as the command arguments.
- Read `../../commands/propose.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace, changing durable user configuration, or creating GitHub issues.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
