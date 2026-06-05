# Changelog

All notable changes are documented in [GitHub Releases](https://github.com/JFK/gh-issue-driven/releases).

## [Unreleased]

### Changed
- **Post-PR review is now opt-in.** `review.provider` defaults to `none`; `/ship` creates the PR and stops unless review is explicitly configured or `/goal` runs it. (#83)
- `/ship` delegates the review loop to `/gh-issue-driven:review` (now its canonical home); `ship.md` is ~40% smaller. (#83)
- New `review.model` (`auto|haiku|sonnet|opus`, default `auto`) right-sizes the fix-application model. `goal.inner_review.model` default is now `auto`. (#83)

### Deprecated
- `copilot.enabled` is no longer consulted — use `review.provider`. (#83)

## [v0.12.1](https://github.com/JFK/gh-issue-driven/releases/tag/v0.12.1) — 2026-06-05

## [v0.12.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.12.0) — 2026-06-04

## [v0.11.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.11.0) — 2026-05-30

## [v0.10.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.10.0) — 2026-05-29

## [v0.9.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.9.0) — 2026-05-19

## [v0.8.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.8.0) — 2026-04-18

## [v0.7.1](https://github.com/JFK/gh-issue-driven/releases/tag/v0.7.1) — 2026-04-14

## [v0.7.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.7.0) — 2026-04-12

## [v0.6.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.6.0) — 2026-04-12

## [v0.5.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.5.0) — 2026-04-12

## [v0.4.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.4.0) — 2026-04-12

## [v0.3.1](https://github.com/JFK/gh-issue-driven/releases/tag/v0.3.1) — 2026-04-12

## [v0.3.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.3.0) — 2026-04-11

## [v0.2.1](https://github.com/JFK/gh-issue-driven/releases/tag/v0.2.1) — 2026-04-11

## [v0.2.0](https://github.com/JFK/gh-issue-driven/releases/tag/v0.2.0) — 2026-04-10

> **Dogfooding checklist exemption**: v0.2.0 was tagged before the [Release checklist](CONTRIBUTING.md#release-checklist--dogfooding-gate) was established (see #8, introduced after v0.2.0). This release has no dogfooding evidence bundle attached. Releases after v0.2.0 are required to follow the checklist.

## [v0.1.2](https://github.com/JFK/gh-issue-driven/releases/tag/v0.1.2) — 2026-04-10

## [v0.1.1](https://github.com/JFK/gh-issue-driven/releases/tag/v0.1.1) — 2026-04-10
