---
name: gh-issue-driven-tag
description: "Use when the user asks to run /gh-issue-driven:tag, prepare a release from a milestone, update release notes, bump manifests, create a tag, or create a GitHub release."
---

# gh-issue-driven:tag

This skill exposes the gh-issue-driven command to Codex.

When invoked:

- Treat the user's request after `gh-issue-driven:tag`, `/gh-issue-driven:tag`, or `gh-issue-driven tag` as the command arguments.
- Read `../../commands/tag.md` and follow it as the source of truth.
- Preserve the command's trust boundary. In Codex, request permission before writing outside the current workspace, changing durable user configuration, creating tags, pushing branches, or creating GitHub releases.
- Translate Claude Code command references to available Codex skills or tools when there is a direct equivalent. If a companion plugin is missing, report it and use the fallback behavior specified by the command.
