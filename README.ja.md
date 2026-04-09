# gh-issue-driven

> ⚠️ **Alpha (v0.1.x)** — このプラグインは現在 dogfooding 中です。orchestrated flow は end-to-end で動作しています (PR #15 はこのプラグインが自分自身をレビューして merge されました) が、いくつかの既知の sharp edge があります。本番リポジトリで使う前に下記の [Limitations / 既知の制限事項](#limitations--既知の制限事項) を確認してください。

> **GitHub issue 駆動開発のための2フェーズオーケストレータ。マルチレビュアによる事前レビューゲートと Copilot レビュー自動ループ付き。**

`gh-issue-driven` は [Claude Code](https://claude.com/claude-code) のプラグインで、「issue #142 の作業を始める」を1本の再現可能なワークフローに変えます：

1. **`/gh-issue-driven:start <issue>`** — issue を取得、Kagura Memory から関連する過去ナレッジを recall、**gate1**（設計レビュー、`/claude-c-suite:ask` → 必要なら `/ceo` にエスカレーション）を実行、型付きフィーチャーブランチを作成し、実装フェーズへハンドオフ。
2. _（あなたがコードを書く）_
3. **`/gh-issue-driven:ship`** — **gate2**（audit + cso + qa-lead + cto を並列実行）、PR 作成、**GitHub Copilot レビューループ**を最大5回まで自動実行（PR が approve されるか、対応すべき fb がなくなるまで）。

ワークフロー全体は `kagura-memory` の `session-start` / `session-summary` で挟まれ、issue ごとの学びが永続化されます。

---

## 60秒クイックスタート

```text
# ステップ0 — リポジトリの GitHub Settings ページで一度だけ:
#   Settings → Code review → ☑ Automatic Copilot code review
#   URL: https://github.com/<owner>/<repo>/settings/code-review
#   これを有効にすると、Copilot レビューループが gh CLI のバージョンに依存せず動く。
#   有効化しない場合は gh CLI >= 2.88.0 が必要 (下記「必要なバージョン」参照)。

# Claude Code セッション内 — プラグイン install:
/plugin marketplace add JFK/gh-issue-driven
/plugin install gh-issue-driven

# 推奨 companion プラグイン (無くても degrade して動作)
# 注: install target の `@<marketplace>` は marketplace.json の name フィールド (GitHub repo slug ではない)

/plugin marketplace add JFK/claude-c-suite-plugin    # gate1 + gate2 レビュア
/plugin install claude-c-suite@claude-c-suite

/plugin marketplace add kagura-ai/memory-cloud       # session-start/summary + recall
/plugin install kagura-memory@kagura-memory-cloud

# Optional (v0.2 の深掘りレビュー用):
/plugin marketplace add JFK/claude-phd-panel-plugin
/plugin install claude-phd-panel@claude-phd-panel

# 任意のリポジトリで:
/gh-issue-driven:doctor          # 初回環境チェック (ステップ0 の確認 prompt も走る)
/gh-issue-driven:start 142       # フェーズ1
# ... 実装、その後 /simplify で diff レビュー ...
/gh-issue-driven:ship            # フェーズ2
```

> **ステップ0 が必要な理由**: GitHub の "Automatic Copilot code review" リポジトリ設定を有効にすると、PR 作成時と push のたびに Copilot レビューが自動で要求されるため、gh CLI のバージョンに関係なくループが自走します。有効化していない場合、プラグインは `gh pr edit --add-reviewer @copilot` にフォールバックしますが、これは `gh < 2.88.0` で **silent に no-op します** ([#15](https://github.com/JFK/gh-issue-driven/issues/15) 参照)。`/gh-issue-driven:doctor` は repo ごとに7日間隔でステップ0 の確認 prompt を出し、どちらのモードも使えない場合は hard fail します。

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
2. `/ask` 応答内で最後に出現した `## Verdict:` 行のトークンが `decline` の場合、`/claude-c-suite:ceo` に昇格して3視点 synthesis を実行。（`decline` は同じ `## Verdict:` 行で使われる gate1 専用トークンであり、別チャネルではない。応答本文に "decline" や "escalate" という単語が出てきても、それはレビュアの推論の一部であり routing シグナルではない — 構造化された verdict 行のみがカウントされる。）
3. レビュアの応答末尾の `## Verdict: green|yellow|red` 行から verdict を解析する。構造化行が canonical で last-wins、case は正規化、末尾の句読点は許容。キーワードヒューリスティックは構造化行が無い場合の **fallback のみ** で、warn ログを emit して soft-deprecation の追跡が可能。
4. **green** → 続行 / **yellow** → ユーザー確認 / **red** → abort（`force` で override 可）

### Gate 2 — PR 作成直前のレビューバッテリー（`/gh-issue-driven:ship`）

実装の **後**、PR 作成の **前** に走ります。デフォルトでは **3つの advisor reviewer** が 1ターン内で並列発火 (advisor-only mode)：

| レビュア | 役割 | verdict 型 |
|---|---|---|
| `/claude-c-suite:cso` | セキュリティ | Advisory（`green`/`yellow`/`red`） |
| `/claude-c-suite:qa-lead` | テスト網羅 | Advisory |
| `/claude-c-suite:cto` | 技術負債 | Advisory |

3つの advisor verdict が集約される：いずれか red → red、yellow → yellow、それ以外 green。verdict handling は gate1 と同じ (green → 続行 / yellow → 確認 / red → abort、`force` で override)。

#### Optional binary gate (default off)

「fail なら `force` でも block されるハードバイナリゲート」が欲しいプラグインメンテナは、`~/.claude/gh-issue-driven-config.json` の `gate2.binary_gate` に skill 名を設定できます：

```json
{
  "gate2": {
    "binary_gate": "/claude-c-suite:audit"
  }
}
```

設定すると、その skill が advisor 3つに加えて 4つ目のレビュアとして並列発火し、その verdict (`pass`/`fail`) がハードリリースゲートとして読まれる。

デフォルトは `null` (binary gate なし)。以前のバージョンは `/claude-c-suite:audit` がデフォルトだったが、これは `claude-c-suite-plugin` 自身の規約遵守チェッカーであり、他のプラグイン (gh-issue-driven 含む) では script が存在せずエラーで終わる → 全 `/ship` invocation を block していた。v0.1.1 (#26) で修正。

### Verdict 行の規約

レビュアの skill は、応答末尾に最終的な `## Verdict:` 行を出力すること。トークンは次のいずれか：

- `## Verdict: green`
- `## Verdict: yellow`
- `## Verdict: red`
- `## Verdict: decline`  &nbsp;&nbsp;— gate1 (`/ask`) のみ、routing 昇格シグナル
- `## Verdict: pass`  &nbsp;&nbsp;— `/audit` のみ
- `## Verdict: fail`  &nbsp;&nbsp;— `/audit` のみ

（応答中に複数の `## Verdict:` 行が現れた場合は last-wins が適用される — 下記ルール参照。）

ルール：

- **構造化行が canonical**。`gh-issue-driven` はこの行を最優先で解釈する。
- **last-wins**: 応答中に複数行ある場合、最後の出現が勝つ（"最初は red と思ったが結局 green" のような自然な記述に対応）。
- **case insensitive**: `Green` / `green` / `GREEN` はすべて `green` に正規化される。
- **末尾の句読点 OK**: `## Verdict: green.` のような形式も `\b<token>\b` で許容される。
- **キーワードヒューリスティックは fallback のみ**: 構造化行が無い場合だけ走る。fallback したときは `verdict_parser=heuristic` という warn ログを emit するので、ヒューリスティック完全廃止 (v0.4) の判断材料として追跡可能。
- **`decline` は gate1 routing 専用トークン**: 別チャネルではない。本文中に "decline" の単語が出ても、それは routing シグナルではなくレビュアの推論。

`claude-c-suite` / `claude-phd-panel` などの reviewer skill を保守している場合、この行を出力するように改修すれば統合がよりクリーンになる。

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

### 必要なバージョン (どちらか一方)

Copilot ループには **2つの動作モード**があり、**どちらか一方**が成立していればループが end-to-end で動きます：

- **Mode A (推奨)** — リポジトリ設定で `Settings → Code review → ☑ Automatic Copilot code review` を有効化。**任意の `gh` CLI バージョンで動く**。Copilot が PR 作成時と push のたびに自動で要求される。
- **Mode B** — `gh` CLI **v2.88.0 以降** ([2026年3月の Changelog](https://github.blog/changelog/2026-03-11-request-copilot-code-review-from-github-cli/) で追加された本物の `--add-reviewer @copilot` サポート)。それ以前の `gh` バージョンでは手動 reviewer add が silent に no-op する ([#15](https://github.com/JFK/gh-issue-driven/issues/15) 参照)。

両モード共通: リポジトリのプランで GitHub Copilot code review 機能が利用可能であること。

### Web UI による手動フォールバック

Mode A を有効化できず、`gh` も 2.88.0+ にアップグレードできない場合：

1. プラグインが PR を作成した後、GitHub Web UI で PR を開く。
2. 右サイドバー → Reviewers → "Copilot" をクリック。
3. Copilot のレビューが届いたら `/gh-issue-driven:ship` を再実行する。(resume mode は [#14](https://github.com/JFK/gh-issue-driven/issues/14) で追跡中。)

---

## クロスプラグイン Skill 呼び出しの契約

このプラグインは他プラグインのスラッシュコマンドを **Skill ツール経由で skill として呼び出します**。各ゲートのコマンド本文に明示的に書かれています：

> Invoke `/claude-c-suite:ask` via the Skill tool, passing the prompt block built in step N as input.

並列レビュアの場合 (gate2 で invoke する skill 数は `gate2.binary_gate` の設定で変わる):

> In a single tool-call batch, invoke gate2 reviewer skills in parallel via the Skill tool. **デフォルト (advisor-only mode、`gate2.binary_gate: null`)**: 3 advisor skill — `/claude-c-suite:cso`, `/claude-c-suite:qa-lead`, `/claude-c-suite:cto`。**`gate2.binary_gate` が skill 名 (例: `/claude-c-suite:audit` for plugin maintainers) に設定されている場合**: 4 skill — configured binary gate skill + 3 advisor。

skill が見つからない場合の degrade：
- advisor reviewer missing → そのゲートスロットは `unknown`、警告を出して継続
- binary gate skill missing (`gate2.binary_gate` 設定時のみ該当) → `unknown` 扱い、`force` で続行可
- `gate2.binary_gate` が `null` (デフォルト) → binary gate なし、advisor-only mode、`force` 不要
- `kagura-memory` missing → recall と session-start/summary をスキップ (`memory.context_id` resolution 失敗時は warning 1行を出す)

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
| `gate2.binary_gate` | `null` (off) | optional な override 不可バイナリゲート。skill 名 (例: `/claude-c-suite:audit`) を設定すると有効化 |
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
| [`kagura-memory`](https://github.com/kagura-ai/memory-cloud) | optional | session-start/summary と recall |

---

## Limitations / 既知の制限事項

`gh-issue-driven` は alpha software (v0.1.x) です。orchestrated flow は real PR で end-to-end 動作しています (このプラグインは `JFK/gh-issue-driven` で自分自身の PR を ship した実績あり) が、v0.1.1 時点で以下の既知の sharp edge があります。データ損失や state corruption は無いものの、operator experience に影響します:

- **遅い Mode A repo で `silent_no_op` の false-positive** ([#23](https://github.com/JFK/gh-issue-driven/issues/23)) — `/gh-issue-driven:ship` step 13 の bounded wait は 30秒。GitHub の "Automatic Copilot code review" auto-review が 30秒以上かかる repo (`JFK/gh-issue-driven` で実測 ~4分) では wait が expire し、loop が誤って skip され `exit_reason=silent_no_op` が記録される。state file の診断は正しいので、Copilot review が landing したら `/ship` を再実行すれば復旧可能。アーキテクチャ的な修正は #23 で追跡 (検出を step 14 の polling loop に移動)。
- **resume mode 無し** ([#14](https://github.com/JFK/gh-issue-driven/issues/14)) — `/ship` が loop の途中で exit した場合 (test failure, 手動中断, silent_no_op)、再実行すると現在は resume せずに全 gate が再実行される。
- **`memory.context_id` のデフォルトは placeholder name** ([#12](https://github.com/JFK/gh-issue-driven/issues/12) — このリリースで実装) — `memory.context_id` は UUID または context name (case-insensitive、実行時に `list_contexts` で UUID 解決) のどちらも受け付けるようになった。デフォルト値は `gh-issue-driven-dev` という honest な plugin-named placeholder。kagura-memory を install しているユーザーは、自分の環境の有効な context 名 (case-insensitive match) または UUID に上書きすること。kagura-memory を使わないユーザーはこのフィールドを無視できる (recall は自動 skip)。Resolution failure (name not found / ambiguous / list_contexts errors) は **warning を1行出して** recall をスキップし `/start` は続行する (warning があるので silent ではない)。**現状 `/gh-issue-driven:doctor` が configured context_id の解決を validate しない**のは v0.1.2 の follow-up として追跡。
- **loop state machine のテスト無し** — verdict parser と Copilot detection function は fixture-driven test されているが、step 14 polling loop の 5 つの terminal `exit_reason` state は自動テストで cover されていない (v0.2.0+ で [#3](https://github.com/JFK/gh-issue-driven/issues/3) と一緒に対応予定)。
- **`claude-c-suite:audit` がこのプラグインを評価できない** — audit skill の `scripts/audit.py` がこのプラグインの layout に存在しない。de-facto baseline は `lint.yml` (frontmatter 検証、JSON syntax、version sync、fixture test、inline-jq sync を validate)。v0.1.1 hardening tail の follow-up として filed。
- **PR body の secret-like 値を自動検出しない** ([#7](https://github.com/JFK/gh-issue-driven/issues/7)) — プラグインは commit message と diff context から PR body を生成する。v0.2.0 で secret-scan abort を追加予定。

既知 issue の全リストは [v0.1.1](https://github.com/JFK/gh-issue-driven/milestone/1)、[v0.1.2](https://github.com/JFK/gh-issue-driven/milestone/4)、[v0.2.0](https://github.com/JFK/gh-issue-driven/milestone/2) の milestone を参照してください。

---

## ライセンス

[MIT](LICENSE) © Fumikazu Kiyota

---

🤖 [Claude Code](https://claude.com/claude-code) で作りました。
