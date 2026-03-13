# apps-script-fleet Example Projects Design

## Overview

apps-script-fleet テンプレートから実際に「Use this template」で生成する 3 つの example リポジトリ。実用的な GAS プロジェクトとして動作しつつ、テンプレートのショーケースとしても機能する。

## Goals

- テンプレートの「1 repo = 1 function」思想を example 自体が体現する
- GAS の 3 大パターン（カスタム関数 / トリガー駆動 / Web App）を網羅する
- ユーザーが自分のユースケースに近い example をクローンして始められる

## Common Design Principles

### Repository Creation

- GitHub で `apps-script-fleet` を template として `Use this template` で各リポを生成
- `src/`, `test/`, `appsscript.json`, `README.md` を書き換える。ビルド・CI/CD・lint 設定はテンプレートそのまま

### Architecture Pattern

- GAS 固有 API（HtmlService, SpreadsheetApp, GmailApp, UrlFetchApp, PropertiesService）は `src/index.ts` に閉じ込める
- テスト可能なビジネスロジックは別モジュールに純粋関数として分離
- `src/index.ts` はカバレッジ対象外（テンプレートの既存設定を踏襲）
- エントリポイント関数には `export` をつけない（GAS ランタイム制約）

### Naming Convention

- リポジトリ prefix: `apps-script-`

### Implementation Notes

- **HTML なしの example**: テンプレートの build スクリプトは `cp src/*.html dist/` を実行する。HTML ファイルがない example（custom-functions, slack-notifier）では、build スクリプトの該当行を調整するか、空の placeholder HTML を置く
- **`appsscript.json` の `webapp` セクション**: テンプレートには `webapp` ブロックが含まれるが、Web App でない example（custom-functions, slack-notifier）では削除する
- **oauthScopes は完全 URL**: spec 中の短縮表記は実装時に完全 URL に変換する（例: `script.external_request` → `https://www.googleapis.com/auth/script.external_request`）
- **`verbatimModuleSyntax`**: 型のみの import は `import type` 構文を使用すること

---

## Example 1: `apps-script-custom-functions`

### Purpose

Spreadsheet カスタム関数 — 日本ビジネス向けデータ検証。セルから `=IS_VALID_EMAIL("test@example.com")` のように呼び出す。

### Functions

| カスタム関数 | 説明 |
|------------|------|
| `=IS_VALID_EMAIL(value)` | メールアドレス形式チェック |
| `=IS_VALID_PHONE_JP(value)` | 日本の電話番号形式チェック（固定・携帯・フリーダイヤル） |
| `=IS_VALID_POSTAL_CODE(value)` | 郵便番号形式チェック（ハイフンあり/なし対応） |

### File Structure

```
src/index.ts              — GAS エントリ: IS_VALID_EMAIL(), IS_VALID_PHONE_JP(), IS_VALID_POSTAL_CODE()
                            各関数は validators.ts に委譲するだけ
src/validators.ts         — 正規表現ベースの検証ロジック（純粋関数、export あり）
test/validators.test.ts   — 正常系・異常系・エッジケース（空文字、null、ハイフンあり/なし等）
appsscript.json           — oauthScopes: []（外部アクセス不要）
```

### Key Characteristics

- HTML なし、トリガーなし（セルから直接呼び出し）
- 外部 API 不要 — 純粋関数のみで完結
- テンプレートの中で最もシンプルな構成

### Template Features Demonstrated

- ロジック分離（index.ts → modules）
- 純粋関数テスト 80%+
- export なしエントリポイント制約
- カスタム関数パターン

---

## Example 2: `apps-script-slack-notifier`

### Purpose

Spreadsheet に行が追加されたら Slack App Bot Token（`chat.postMessage` API）で通知する。

### Flow

1. 時限トリガー（5 分ごと）で `checkNewRows()` 実行
2. 最終処理行を ScriptProperties で管理
3. 新しい行があれば `chat.postMessage` API で Slack に POST
4. `setSlackConfig(token, channelId)` で初期設定

### File Structure

```
src/index.ts              — GAS エントリ: checkNewRows(), setSlackConfig()
                            SpreadsheetApp + PropertiesService + UrlFetchApp を使う統合層
src/sheet-reader.ts       — extractNewRows(allRows, lastProcessedIndex): 差分抽出の純粋関数
src/slack-message.ts      — buildSlackPayload(rows, channelId): Slack API リクエストボディ構築の純粋関数
test/sheet-reader.test.ts — 行追加あり/なし、空シート、ヘッダーのみ
test/slack-message.test.ts — 1行/複数行、特殊文字エスケープ
appsscript.json           — oauthScopes: [script.external_request, spreadsheets]
```

### Key Characteristics

- HTML なし
- トリガー駆動（ユーザーが手動で `checkNewRows` にトリガー設定）
- 外部 API 連携（UrlFetchApp → Slack chat.postMessage）
- 状態管理（PropertiesService で最終処理行を永続化）

### Template Features Demonstrated

- ロジック分離（index.ts → modules）
- 純粋関数テスト 80%+
- export なしエントリポイント制約
- 外部 API 連携（UrlFetchApp）
- 状態管理（PropertiesService）
- トリガー駆動パターン

---

## Example 3: `apps-script-form-mailer`

### Purpose

お問い合わせフォーム Web App。doGet でフォーム表示、doPost で送信 → 管理者に Gmail 通知。

### Flow

1. `doGet()` でフォーム HTML を返す
2. ユーザーが名前・メール・本文を入力して送信
3. `doPost(e)` で受信 → 入力バリデーション → 管理者に GmailApp で通知メール
4. 送信結果（成功 / エラー）を HTML で返す

### File Structure

```
src/index.ts              — GAS エントリ: doGet(), doPost(e)
                            バリデーション → メール送信 → 結果HTML返却
src/form-validator.ts     — validateFormInput({ name, email, body }): バリデーション結果を返す純粋関数
src/mail-builder.ts       — buildMailOptions({ name, email, body }): 件名・HTML本文を組み立てる純粋関数
src/form.html             — お問い合わせフォーム（名前、メール、本文）
src/result.html           — 送信結果表示（成功/エラー）
test/form-validator.test.ts — 必須項目欠落、メール形式不正、正常入力
test/mail-builder.test.ts — 件名フォーマット、HTMLエスケープ、長文
appsscript.json           — oauthScopes: [gmail.send]
```

### Key Characteristics

- Web App パターン（doGet + doPost）
- HTML ファイル 2 つ（フォーム + 結果）— Stylelint / HTMLHint が活きる
- Gmail 連携
- トリガーなし（Web App として公開）

### Template Features Demonstrated

- ロジック分離（index.ts → modules）
- 純粋関数テスト 80%+
- export なしエントリポイント制約
- HTML + Stylelint / HTMLHint
- Web App パターン（doGet / doPost）

---

## Coverage Matrix

| テンプレート機能 | custom-functions | slack-notifier | form-mailer |
|----------------|:---:|:---:|:---:|
| ロジック分離 (index.ts → modules) | o | o | o |
| 純粋関数テスト 80%+ | o | o | o |
| export なしエントリポイント | o | o | o |
| HTML + Stylelint/HTMLHint | | | o |
| 外部 API (UrlFetchApp) | | o | |
| 状態管理 (PropertiesService) | | o | |
| Web App (doGet/doPost) | | | o |
| カスタム関数 | o | | |
| トリガー駆動 | | o | |

## Implementation Order

3 つのリポジトリは互いに独立しているため、並列に実装可能。複雑度順に並べると：

1. `apps-script-custom-functions` — 最もシンプル（純粋関数のみ）
2. `apps-script-slack-notifier` — 中程度（外部API + 状態管理）
3. `apps-script-form-mailer` — 最も多機能（Web App + HTML + Gmail）
