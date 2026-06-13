---
name: gh-issue-driven-doctor
description: "Use when the user asks to run /gh-issue-driven:doctor, diagnose the gh-issue-driven environment, check GitHub CLI auth, plugin availability, config health, or workflow readiness."
---

# gh-issue-driven:doctor

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:doctor`, `/gh-issue-driven:doctor`, or `gh-issue-driven doctor` as the command arguments.
- Read `../../commands/doctor.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace or changing durable user configuration.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
