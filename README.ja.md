# gh-issue-driven

> **GitHub issue 駆動開発のための2フェーズオーケストレータ。マルチレビュアによる事前レビューゲートと Copilot レビュー自動ループ付き。**

`gh-issue-driven` は [Claude Code](https://claude.com/claude-code) のプラグインで、「issue #142 の作業を始める」を1本の再現可能なワークフローに変えます：

1. **`/gh-issue-driven:start <issue>`** — issue を取得、Kagura Memory から関連する過去ナレッジを recall、**gate1**（設計レビュー、`/claude-c-suite:ask` → 必要なら `/ceo` にエスカレーション）を実行、型付きフィーチャーブランチを作成し、実装フェーズへハンドオフ。
2. _（あなたがコードを書く）_
3. **`/gh-issue-driven:ship`** — **gate2**（audit + cso + qa-lead + cto を並列実行）、PR 作成、**GitHub Copilot レビューループ**を最大5回まで自動実行（PR が approve されるか、対応すべき fb がなくなるまで）。

ワークフロー全体は `kagura-memory` の `session-start` / `session-summary` で挟まれ、issue ごとの学びが永続化されます。

---

## 60秒クイックスタート

```text
# Claude Code セッション内:
/plugin marketplace add JFK/gh-issue-driven
/plugin install gh-issue-driven

# 任意のリポジトリで:
/gh-issue-driven:doctor          # 初回環境チェック
/gh-issue-driven:start 142       # フェーズ1
# ... 実装 ...
/gh-issue-driven:ship            # フェーズ2
```

---

## コマンド一覧

| コマンド | 動作 |
|---|---|
| `/gh-issue-driven:start <issue> [flags]` | issue 取得、gate1、ブランチ作成。フラグ: `dry-run`, `force`, `no-memory` |
| `/gh-issue-driven:ship [flags]` | gate2、PR 作成、Copilot ループ、session 保存。フラグ: `dry-run`, `force`, `no-copilot`, `draft` |
| `/gh-issue-driven:doctor [verbose|fix]` | read-only な環境健康診断 |
| `/gh-issue-driven:config [show|init|path|<key>]` | 実効設定の表示、テンプレート初期化 |
| `/gh-issue-driven:status [<branch>|all]` | カレントブランチ（または全ブランチ）の state 表示 |

---

## ゲートの仕組み

### Gate 1 — 設計レビュー（`/gh-issue-driven:start`）

issue 取得と recall の **後**、ブランチ作成の **前** に走ります。戦略：

1. まず `/claude-c-suite:ask`（単一視点ルータ）を呼ぶ。軽量・高速で、専門1分野で済む issue に最適。
2. `/ask` が decline（`DECLINE` / `needs synthesis` / `requires multiple lenses` / `escalate` を出力に含む）した場合、`/claude-c-suite:ceo` に昇格して3視点 synthesis を実行。
3. レビュアの応答末尾の `## Verdict: green|yellow|red` 行から verdict を解析（無ければヒューリスティック）。
4. **green** → 続行 / **yellow** → ユーザー確認 / **red** → abort（`force` で override 可）

### Gate 2 — PR 作成直前のレビューバッテリー（`/gh-issue-driven:ship`）

実装の **後**、PR 作成の **前** に走ります。4つのレビュアが **1ターン内で並列発火**：

| レビュア | 役割 | verdict 型 |
|---|---|---|
| `/claude-c-suite:audit` | 規約遵守監査 | **Binary**（`pass`/`fail`）— ハードゲート |
| `/claude-c-suite:cso` | セキュリティ | Advisory（`green`/`yellow`/`red`） |
| `/claude-c-suite:qa-lead` | テスト網羅 | Advisory |
| `/claude-c-suite:cto` | 技術負債 | Advisory |

**`/audit` はハードゲート**。fail なら `force` でも PR 作成を中止。advisor 3つは集約：いずれか red → red、yellow → yellow、それ以外 green。

### Verdict 行の規約

レビュアの skill には、応答末尾に以下を含めることを推奨：

```
## Verdict: green
```

（または `yellow` / `red` / `/audit` なら `pass` / `fail`）。`gh-issue-driven` はこの行を最優先で解釈し、無ければキーワードヒューリスティックにフォールバックします。

---

## Copilot レビューループ

`gh pr create` の後、`/gh-issue-driven:ship` は次のように動きます：

```text
gh pr edit <num> --add-reviewer @copilot
```

そして **最大5ループ**（設定可）回します：

1. `gh pr view --json reviews,comments,reviewDecision` を 60秒ごとに poll、最大15分待機
2. 最新レビューと新しい bot コメントをパース
3. **終了条件**：`APPROVED` / 対応すべき fb なし / max loops 到達 / "no issues found" 系のみ
4. actionable なコメントは `Edit` / `Bash` で実適用、nit はスキップ
5. `copilot.run_tests_after_edits` が true ならローカルテスト実行
6. `fix: address Copilot review (loop N)` で commit、push、レビュー再依頼

ループは **never-blocking**：5周使い切っても PR は開いたまま、残りは手動で対応してもらいます。

### 必要なバージョン

- `gh` CLI v2.88.0 以降（Copilot reviewer サポート、[2026年3月の Changelog](https://github.blog/changelog/2026-03-11-request-copilot-code-review-from-github-cli/)）
- リポジトリで GitHub Copilot code review が有効化されていること

---

## クロスプラグイン Skill 呼び出しの契約

このプラグインは他プラグインのスラッシュコマンドを **Skill ツール経由で skill として呼び出します**。各ゲートのコマンド本文に明示的に書かれています：

> Invoke `/claude-c-suite:ask` via the Skill tool, passing the prompt block built in step N as input.

並列レビュアの場合：

> In a single tool-call batch, invoke all four reviewer skills in parallel via the Skill tool: `/claude-c-suite:audit`, `/claude-c-suite:cso`, `/claude-c-suite:qa-lead`, `/claude-c-suite:cto`.

skill が見つからない場合の degrade：
- レビュア missing → そのゲートスロットは `unknown`、警告を出して継続
- `/audit` missing（ハードゲート）→ `force` フラグが必要
- `kagura-memory` missing → recall と session-start/summary をスキップ

`/gh-issue-driven:doctor` で何が入っているか確認できます。

---

## 設定

デフォルトはバンドル済み。`~/.claude/gh-issue-driven-config.json` で上書き可能：

```bash
/gh-issue-driven:config init      # テンプレート書き出し（既存があれば上書きしない）
/gh-issue-driven:config show      # 実効設定表示
/gh-issue-driven:config path      # ファイルパス表示
/gh-issue-driven:config copilot.max_loops   # 単一値表示
```

主な設定：

| キー | デフォルト | 備考 |
|---|---|---|
| `default_branch` | `main` | base ブランチ |
| `gate1.primary` | `/claude-c-suite:ask` | gate1 の最初のレビュア |
| `gate1.fallback` | `/claude-c-suite:ceo` | decline 時のエスカレーション先 |
| `gate2.binary_gate` | `/claude-c-suite:audit` | override 不可ハードゲート |
| `gate2.advisors` | `[cso, qa-lead, cto]` | 並列実行・集約 |
| `copilot.max_loops` | `5` | 最大ループ数 |
| `copilot.poll_interval_sec` | `60` | poll 間隔 |
| `copilot.max_wait_sec` | `900` | 1ループあたりの最大待機時間 |
| `copilot.run_tests_after_edits` | `true` | Copilot 修正後にローカルテスト実行 |

---

## State ファイル

`gh-issue-driven` が追跡している各ブランチには state ファイルがあります：

```text
~/.claude/cache/gh-issue-driven/<branch-flat>.json
~/.claude/cache/gh-issue-driven/<branch-flat>.gate1.md
~/.claude/cache/gh-issue-driven/<branch-flat>.gate2.md
```

`/gh-issue-driven:status` でこれらを整形表示できます。

---

## 必要な依存

| ツール | 必須 | 用途 |
|---|---|---|
| `gh` v2.88.0+ | 必須 | issue/PR 操作、Copilot reviewer |
| `git` | 必須 | ブランチ操作 |
| `jq` | 必須 | JSON パース |
| `python3` | 推奨 | 一部ヘルパー |
| [`claude-c-suite`](https://github.com/JFK/claude-c-suite-plugin) | 推奨 | gate1/gate2 レビュア（無くても degrade して動く） |
| [`claude-phd-panel`](https://github.com/JFK/claude-phd-panel-plugin) | optional | v0.2 の深掘りレビュー用 |
| [`kagura-memory`](https://github.com/JFK/memory-cloud) | optional | session-start/summary と recall |

---

## ライセンス

[MIT](LICENSE) © Fumikazu Kiyota

---

🤖 [Claude Code](https://claude.com/claude-code) で作りました。
