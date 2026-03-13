# Example Projects Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** apps-script-fleet テンプレートから 3 つの実用的な example リポジトリを作成する

**Architecture:** 各リポジトリはテンプレートから `gh repo create --template` で生成し、`src/`, `test/`, `appsscript.json` を書き換える。ビルド・CI/CD・lint 設定はテンプレートそのまま。GAS 固有 API は `src/index.ts` に閉じ込め、テスト可能な純粋関数を別モジュールに分離する。

**Tech Stack:** TypeScript, Jest (ts-jest), Rollup, ESLint, Google Apps Script types

**Spec:** `docs/superpowers/specs/2026-03-14-example-projects-design.md`

---

## Chunk 1: apps-script-custom-functions

### File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `src/index.ts` | GAS エントリ: `IS_VALID_EMAIL()`, `IS_VALID_PHONE_JP()`, `IS_VALID_POSTAL_CODE()` |
| Create | `src/validators.ts` | 正規表現ベースの検証ロジック（純粋関数） |
| Modify | `test/greeting.test.ts` → Delete | テンプレートのサンプルテスト削除 |
| Delete | `src/greeting.ts` | テンプレートのサンプルモジュール削除 |
| Delete | `src/app.html` | HTML 不要（カスタム関数） |
| Create | `test/validators.test.ts` | 検証ロジックのテスト |
| Modify | `appsscript.json` | `webapp` セクション削除、`oauthScopes: []` |
| Modify | `package.json` | `name` 変更、build スクリプトの HTML コピー削除 |
| Modify | `README.md` | プロジェクト固有の説明に書き換え |

---

### Task 1: リポジトリ作成と初期クリーンアップ

**Files:**
- Create: リポジトリ `h13/apps-script-custom-functions` from template
- Delete: `src/greeting.ts`, `src/app.html`, `test/greeting.test.ts`
- Modify: `package.json`, `appsscript.json`

- [ ] **Step 1: テンプレートからリポジトリを作成**

```bash
gh repo create h13/apps-script-custom-functions --template h13/apps-script-fleet --public --clone
cd apps-script-custom-functions
```

- [ ] **Step 2: テンプレートのサンプルファイルを削除し index.ts をスタブ化**

```bash
rm src/greeting.ts src/app.html test/greeting.test.ts
```

`src/index.ts` を空のスタブに置換（旧コードが `greeting.ts` を import しており typecheck が失敗するため）:

```typescript
// GAS entry points will be added in Task 4
```

- [ ] **Step 3: package.json の name を変更**

`package.json` の `"name"` を `"apps-script-custom-functions"` に変更。

build スクリプトから `cp src/*.html dist/` を削除:

```json
"build": "pnpm run clean && pnpm run bundle && cp appsscript.json dist/appsscript.json"
```

- [ ] **Step 4: appsscript.json を更新**

`webapp` セクションを削除、`oauthScopes` を空配列に:

```json
{
  "timeZone": "Asia/Tokyo",
  "dependencies": {},
  "exceptionLogging": "STACKDRIVER",
  "runtimeVersion": "V8",
  "oauthScopes": []
}
```

- [ ] **Step 5: 依存関係をインストールして動作確認**

```bash
pnpm install
pnpm run typecheck
```

Expected: 成功（src/index.ts はスタブのみ）

- [ ] **Step 6: コミット**

```bash
git add -A
git commit -m "chore: clean up template for custom functions project"
```

---

### Task 2: validators.ts — テスト作成（RED）

**Files:**
- Create: `test/validators.test.ts`

- [ ] **Step 1: テストファイルを作成**

```typescript
import {
  isValidEmail,
  isValidPhoneJp,
  isValidPostalCode,
} from "../src/validators.js";

describe("isValidEmail", () => {
  it.each([
    ["user@example.com", true],
    ["user.name+tag@example.co.jp", true],
    ["user@subdomain.example.com", true],
  ])("returns true for valid email: %s", (input, expected) => {
    expect(isValidEmail(input)).toBe(expected);
  });

  it.each([
    ["", false],
    ["plaintext", false],
    ["@no-local.com", false],
    ["no-domain@", false],
    ["spaces in@email.com", false],
    ["missing@.com", false],
  ])("returns false for invalid email: %s", (input, expected) => {
    expect(isValidEmail(input)).toBe(expected);
  });
});

describe("isValidPhoneJp", () => {
  it.each([
    ["03-1234-5678", true],
    ["0312345678", true],
    ["090-1234-5678", true],
    ["09012345678", true],
    ["0120-123-456", true],
    ["0120123456", true],
    ["080-1234-5678", true],
    ["070-1234-5678", true],
    ["045-123-4567", true],
    ["0451234567", true],
  ])("returns true for valid JP phone: %s", (input, expected) => {
    expect(isValidPhoneJp(input)).toBe(expected);
  });

  it.each([
    ["", false],
    ["1234567890", false],
    ["03-1234-567", false],
    ["+81-3-1234-5678", false],
    ["abc-defg-hijk", false],
    ["03-1234-56789", false],
  ])("returns false for invalid JP phone: %s", (input, expected) => {
    expect(isValidPhoneJp(input)).toBe(expected);
  });
});

describe("isValidPostalCode", () => {
  it.each([
    ["123-4567", true],
    ["1234567", true],
    ["000-0000", true],
  ])("returns true for valid postal code: %s", (input, expected) => {
    expect(isValidPostalCode(input)).toBe(expected);
  });

  it.each([
    ["", false],
    ["123-456", false],
    ["12-34567", false],
    ["1234-567", false],
    ["abcdefg", false],
    ["123-45678", false],
  ])("returns false for invalid postal code: %s", (input, expected) => {
    expect(isValidPostalCode(input)).toBe(expected);
  });
});
```

- [ ] **Step 2: テスト実行 — 失敗を確認**

```bash
pnpm run test
```

Expected: FAIL — `Cannot find module '../src/validators.js'`

- [ ] **Step 3: コミット**

```bash
git add test/validators.test.ts
git commit -m "test: add validators test cases (RED)"
```

---

### Task 3: validators.ts — 実装（GREEN）

**Files:**
- Create: `src/validators.ts`

- [ ] **Step 1: validators.ts を実装**

```typescript
export function isValidEmail(value: string): boolean {
  if (value === "") return false;
  const pattern = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$/;
  return pattern.test(value);
}

export function isValidPhoneJp(value: string): boolean {
  if (value === "") return false;
  const patterns = [
    /^0\d-\d{4}-\d{4}$/, // 固定電話（2桁市外局番）: 03-1234-5678
    /^0\d{9}$/, // 固定電話（ハイフンなし）: 0312345678
    /^0\d{2}-\d{3,4}-\d{4}$/, // 固定電話（3桁市外局番）: 045-123-4567
    /^0[789]0-\d{4}-\d{4}$/, // 携帯: 090-1234-5678
    /^0[789]0\d{8}$/, // 携帯（ハイフンなし）: 09012345678
    /^0120-\d{3}-\d{3}$/, // フリーダイヤル: 0120-123-456
    /^0120\d{6}$/, // フリーダイヤル（ハイフンなし）: 0120123456
  ];
  return patterns.some((p) => p.test(value));
}

export function isValidPostalCode(value: string): boolean {
  if (value === "") return false;
  const pattern = /^\d{3}-?\d{4}$/;
  return pattern.test(value);
}
```

- [ ] **Step 2: テスト実行 — 成功を確認**

```bash
pnpm run test
```

Expected: PASS, coverage 80%+

- [ ] **Step 3: コミット**

```bash
git add src/validators.ts
git commit -m "feat: implement data validation functions (GREEN)"
```

---

### Task 4: index.ts — GAS エントリポイント

**Files:**
- Modify: `src/index.ts`

- [ ] **Step 1: src/index.ts を書き換え**

```typescript
import { isValidEmail, isValidPhoneJp, isValidPostalCode } from "./validators.js";

function IS_VALID_EMAIL(value: string): boolean {
  return isValidEmail(value);
}

function IS_VALID_PHONE_JP(value: string): boolean {
  return isValidPhoneJp(value);
}

function IS_VALID_POSTAL_CODE(value: string): boolean {
  return isValidPostalCode(value);
}
```

注意: `export` なし（GAS ランタイム制約）。ESLint の `no-unused-vars` は `src/index.ts` に対して無効化済み。

- [ ] **Step 2: 全チェック実行**

```bash
pnpm run check
```

Expected: PASS（lint + typecheck + test すべて通る）

- [ ] **Step 3: ビルド確認**

```bash
pnpm run build
cat dist/index.js
```

Expected: `dist/index.js` に 3 つの関数がバンドルされている

- [ ] **Step 4: コミット**

```bash
git add src/index.ts
git commit -m "feat: add GAS entry points for custom functions"
```

---

### Task 5: README.md 更新と最終確認

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README.md を書き換え**

プロジェクト概要、使い方（Spreadsheet へのデプロイ手順、カスタム関数の使い方）、テンプレートからの生成方法を記載。

- [ ] **Step 2: 最終チェック**

```bash
pnpm run check && pnpm run build
```

Expected: すべて PASS

- [ ] **Step 3: コミット & プッシュ**

```bash
git add README.md
git commit -m "docs: add project README"
git push origin main
```

---

## Chunk 2: apps-script-slack-notifier

### File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `src/index.ts` | GAS エントリ: `checkNewRows()`, `setSlackConfig()` |
| Create | `src/sheet-reader.ts` | 行データ差分抽出ロジック（純粋関数） |
| Create | `src/slack-message.ts` | Slack API payload 構築（純粋関数） |
| Delete | `src/greeting.ts` | テンプレートのサンプル削除 |
| Delete | `src/app.html` | HTML 不要 |
| Delete | `test/greeting.test.ts` | テンプレートのサンプルテスト削除 |
| Create | `test/sheet-reader.test.ts` | 差分抽出ロジックのテスト |
| Create | `test/slack-message.test.ts` | payload 構築のテスト |
| Modify | `appsscript.json` | `webapp` セクション削除、scopes 変更 |
| Modify | `package.json` | `name` 変更、build スクリプトの HTML コピー削除 |
| Modify | `README.md` | プロジェクト固有の説明 |

---

### Task 6: リポジトリ作成と初期クリーンアップ

**Files:**
- Create: リポジトリ `h13/apps-script-slack-notifier` from template
- Delete: `src/greeting.ts`, `src/app.html`, `test/greeting.test.ts`
- Modify: `package.json`, `appsscript.json`

- [ ] **Step 1: テンプレートからリポジトリを作成**

```bash
gh repo create h13/apps-script-slack-notifier --template h13/apps-script-fleet --public --clone
cd apps-script-slack-notifier
```

- [ ] **Step 2: テンプレートのサンプルファイルを削除し index.ts をスタブ化**

```bash
rm src/greeting.ts src/app.html test/greeting.test.ts
```

`src/index.ts` を空のスタブに置換:

```typescript
// GAS entry points will be added in Task 11
```

- [ ] **Step 3: package.json の name を変更**

`"name"` を `"apps-script-slack-notifier"` に変更。

build スクリプトから `cp src/*.html dist/` を削除:

```json
"build": "pnpm run clean && pnpm run bundle && cp appsscript.json dist/appsscript.json"
```

- [ ] **Step 4: appsscript.json を更新**

```json
{
  "timeZone": "Asia/Tokyo",
  "dependencies": {},
  "exceptionLogging": "STACKDRIVER",
  "runtimeVersion": "V8",
  "oauthScopes": [
    "https://www.googleapis.com/auth/script.external_request",
    "https://www.googleapis.com/auth/spreadsheets"
  ]
}
```

- [ ] **Step 5: 依存関係をインストール**

```bash
pnpm install
pnpm run typecheck
```

- [ ] **Step 6: コミット**

```bash
git add -A
git commit -m "chore: clean up template for slack notifier project"
```

---

### Task 7: sheet-reader.ts — テスト作成（RED）

**Files:**
- Create: `test/sheet-reader.test.ts`

- [ ] **Step 1: テストファイルを作成**

```typescript
import { extractNewRows } from "../src/sheet-reader.js";

describe("extractNewRows", () => {
  it("returns empty array when no new rows", () => {
    const allRows = [
      ["Name", "Email"],
      ["Alice", "alice@example.com"],
    ];
    const result = extractNewRows(allRows, 2);
    expect(result).toEqual([]);
  });

  it("returns new rows after lastProcessedIndex", () => {
    const allRows = [
      ["Name", "Email"],
      ["Alice", "alice@example.com"],
      ["Bob", "bob@example.com"],
    ];
    const result = extractNewRows(allRows, 1);
    expect(result).toEqual([
      { index: 2, data: ["Alice", "alice@example.com"] },
      { index: 3, data: ["Bob", "bob@example.com"] },
    ]);
  });

  it("returns all data rows when lastProcessedIndex is 0", () => {
    const allRows = [
      ["Name", "Email"],
      ["Alice", "alice@example.com"],
    ];
    const result = extractNewRows(allRows, 0);
    expect(result).toEqual([
      { index: 1, data: ["Name", "Email"] },
      { index: 2, data: ["Alice", "alice@example.com"] },
    ]);
  });

  it("returns empty array for empty sheet", () => {
    const result = extractNewRows([], 0);
    expect(result).toEqual([]);
  });

  it("returns empty array when lastProcessedIndex equals row count", () => {
    const allRows = [["Name", "Email"]];
    const result = extractNewRows(allRows, 1);
    expect(result).toEqual([]);
  });
});
```

- [ ] **Step 2: テスト実行 — 失敗を確認**

```bash
pnpm run test -- test/sheet-reader.test.ts
```

Expected: FAIL

- [ ] **Step 3: コミット**

```bash
git add test/sheet-reader.test.ts
git commit -m "test: add sheet-reader test cases (RED)"
```

---

### Task 8: sheet-reader.ts — 実装（GREEN）

**Files:**
- Create: `src/sheet-reader.ts`

- [ ] **Step 1: sheet-reader.ts を実装**

```typescript
export interface RowEntry {
  readonly index: number;
  readonly data: readonly string[];
}

export function extractNewRows(
  allRows: readonly (readonly string[])[],
  lastProcessedIndex: number,
): readonly RowEntry[] {
  return allRows.slice(lastProcessedIndex).map((data, i) => ({
    index: lastProcessedIndex + i + 1,
    data,
  }));
}
```

- [ ] **Step 2: テスト実行 — 成功を確認**

```bash
pnpm run test -- test/sheet-reader.test.ts
```

Expected: PASS

- [ ] **Step 3: コミット**

```bash
git add src/sheet-reader.ts
git commit -m "feat: implement sheet row extraction (GREEN)"
```

---

### Task 9: slack-message.ts — テスト作成（RED）

**Files:**
- Create: `test/slack-message.test.ts`

- [ ] **Step 1: テストファイルを作成**

```typescript
import type { RowEntry } from "../src/sheet-reader.js";
import { buildSlackPayload } from "../src/slack-message.js";

describe("buildSlackPayload", () => {
  it("builds payload for single row", () => {
    const rows: readonly RowEntry[] = [
      { index: 2, data: ["Alice", "alice@example.com"] },
    ];
    const result = buildSlackPayload(rows, "C01234567");
    expect(result).toEqual({
      channel: "C01234567",
      text: expect.stringContaining("Alice"),
    });
  });

  it("builds payload for multiple rows", () => {
    const rows: readonly RowEntry[] = [
      { index: 2, data: ["Alice", "alice@example.com"] },
      { index: 3, data: ["Bob", "bob@example.com"] },
    ];
    const result = buildSlackPayload(rows, "C01234567");
    expect(result.channel).toBe("C01234567");
    expect(result.text).toContain("Alice");
    expect(result.text).toContain("Bob");
    expect(result.text).toContain("2 件");
  });

  it("escapes special characters in data", () => {
    const rows: readonly RowEntry[] = [
      { index: 2, data: ["<script>alert('xss')</script>", "test"] },
    ];
    const result = buildSlackPayload(rows, "C01234567");
    expect(result.text).not.toContain("<script>");
    expect(result.text).toContain("&lt;script&gt;");
  });
});
```

- [ ] **Step 2: テスト実行 — 失敗を確認**

```bash
pnpm run test -- test/slack-message.test.ts
```

Expected: FAIL

- [ ] **Step 3: コミット**

```bash
git add test/slack-message.test.ts
git commit -m "test: add slack-message test cases (RED)"
```

---

### Task 10: slack-message.ts — 実装（GREEN）

**Files:**
- Create: `src/slack-message.ts`

- [ ] **Step 1: slack-message.ts を実装**

```typescript
import type { RowEntry } from "./sheet-reader.js";

export interface SlackPayload {
  readonly channel: string;
  readonly text: string;
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function formatRow(row: RowEntry): string {
  const escaped = row.data.map(escapeHtml);
  return `  Row ${row.index}: ${escaped.join(" | ")}`;
}

export function buildSlackPayload(
  rows: readonly RowEntry[],
  channelId: string,
): SlackPayload {
  const header =
    rows.length === 1
      ? "Spreadsheet に新しい行が追加されました:"
      : `Spreadsheet に ${rows.length} 件の新しい行が追加されました:`;

  const body = rows.map(formatRow).join("\n");

  return {
    channel: channelId,
    text: `${header}\n${body}`,
  };
}
```

- [ ] **Step 2: テスト実行 — 成功を確認**

```bash
pnpm run test
```

Expected: PASS, coverage 80%+

- [ ] **Step 3: コミット**

```bash
git add src/slack-message.ts
git commit -m "feat: implement Slack message builder (GREEN)"
```

---

### Task 11: index.ts — GAS エントリポイント

**Files:**
- Modify: `src/index.ts`

- [ ] **Step 1: src/index.ts を書き換え**

```typescript
import { extractNewRows } from "./sheet-reader.js";
import { buildSlackPayload } from "./slack-message.js";

function checkNewRows(): void {
  const props = PropertiesService.getScriptProperties();
  const token = props.getProperty("SLACK_BOT_TOKEN");
  const channelId = props.getProperty("SLACK_CHANNEL_ID");

  if (!token || !channelId) {
    throw new Error(
      "Slack config not set. Run setSlackConfig(token, channelId) first.",
    );
  }

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  const allRows = sheet.getDataRange().getValues() as string[][];
  const lastProcessed = Number(props.getProperty("LAST_PROCESSED_ROW") ?? "1");

  const newRows = extractNewRows(allRows, lastProcessed);
  if (newRows.length === 0) return;

  const payload = buildSlackPayload(newRows, channelId);

  UrlFetchApp.fetch("https://slack.com/api/chat.postMessage", {
    method: "post",
    contentType: "application/json",
    headers: { Authorization: `Bearer ${token}` },
    payload: JSON.stringify(payload),
  });

  props.setProperty("LAST_PROCESSED_ROW", String(allRows.length));
}

function setSlackConfig(token: string, channelId: string): void {
  const props = PropertiesService.getScriptProperties();
  props.setProperty("SLACK_BOT_TOKEN", token);
  props.setProperty("SLACK_CHANNEL_ID", channelId);
}
```

- [ ] **Step 2: 全チェック実行**

```bash
pnpm run check
```

Expected: PASS

- [ ] **Step 3: ビルド確認**

```bash
pnpm run build
```

Expected: `dist/index.js` にバンドル成功

- [ ] **Step 4: コミット**

```bash
git add src/index.ts
git commit -m "feat: add GAS entry points for Slack notifier"
```

---

### Task 12: README.md 更新と最終確認

- [ ] **Step 1: README.md を書き換え**

プロジェクト概要、Slack App の設定手順、トリガー設定方法を記載。

- [ ] **Step 2: 最終チェック**

```bash
pnpm run check && pnpm run build
```

Expected: PASS

- [ ] **Step 3: コミット & プッシュ**

```bash
git add README.md
git commit -m "docs: add project README"
git push origin main
```

---

## Chunk 3: apps-script-form-mailer

### File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `src/index.ts` | GAS エントリ: `doGet()`, `doPost(e)` |
| Create | `src/form-validator.ts` | フォーム入力バリデーション（純粋関数） |
| Create | `src/mail-builder.ts` | メール件名・本文構築（純粋関数） |
| Modify | `src/app.html` → `src/form.html` | お問い合わせフォーム（AJAX 送信 + 結果表示） |
| Delete | `src/greeting.ts` | テンプレートのサンプル削除 |
| Delete | `test/greeting.test.ts` | テンプレートのサンプルテスト削除 |
| Create | `test/form-validator.test.ts` | バリデーションのテスト |
| Create | `test/mail-builder.test.ts` | メール構築のテスト |
| Modify | `appsscript.json` | `oauthScopes` に `gmail.send` |
| Modify | `package.json` | `name` 変更 |
| Modify | `README.md` | プロジェクト固有の説明 |

---

### Task 13: リポジトリ作成と初期クリーンアップ

**Files:**
- Create: リポジトリ `h13/apps-script-form-mailer` from template
- Delete: `src/greeting.ts`, `test/greeting.test.ts`
- Modify: `src/app.html` → `src/form.html`, `package.json`, `appsscript.json`

- [ ] **Step 1: テンプレートからリポジトリを作成**

```bash
gh repo create h13/apps-script-form-mailer --template h13/apps-script-fleet --public --clone
cd apps-script-form-mailer
```

- [ ] **Step 2: テンプレートのサンプルファイルを削除/リネーム、index.ts をスタブ化**

```bash
rm src/greeting.ts test/greeting.test.ts
mv src/app.html src/form.html
```

`src/index.ts` を空のスタブに置換:

```typescript
// GAS entry points will be added in Task 19
```

- [ ] **Step 3: package.json の name を変更**

`"name"` を `"apps-script-form-mailer"` に変更。

build スクリプトはそのまま（`cp src/*.html dist/` で `form.html` と `result.html` がコピーされる）。

- [ ] **Step 4: appsscript.json を更新**

```json
{
  "timeZone": "Asia/Tokyo",
  "dependencies": {},
  "exceptionLogging": "STACKDRIVER",
  "runtimeVersion": "V8",
  "webapp": {
    "access": "ANYONE",
    "executeAs": "USER_DEPLOYING"
  },
  "oauthScopes": [
    "https://www.googleapis.com/auth/gmail.send"
  ]
}
```

- [ ] **Step 5: 依存関係をインストール**

```bash
pnpm install
```

- [ ] **Step 6: コミット**

```bash
git add -A
git commit -m "chore: clean up template for form mailer project"
```

---

### Task 14: form-validator.ts — テスト作成（RED）

**Files:**
- Create: `test/form-validator.test.ts`

- [ ] **Step 1: テストファイルを作成**

```typescript
import { validateFormInput } from "../src/form-validator.js";

describe("validateFormInput", () => {
  it("returns valid for correct input", () => {
    const result = validateFormInput({
      name: "Taro Yamada",
      email: "taro@example.com",
      body: "This is a test message.",
    });
    expect(result).toEqual({ valid: true, errors: [] });
  });

  it("returns error when name is empty", () => {
    const result = validateFormInput({
      name: "",
      email: "taro@example.com",
      body: "Message",
    });
    expect(result.valid).toBe(false);
    expect(result.errors).toContain("名前は必須です");
  });

  it("returns error when email is empty", () => {
    const result = validateFormInput({
      name: "Taro",
      email: "",
      body: "Message",
    });
    expect(result.valid).toBe(false);
    expect(result.errors).toContain("メールアドレスは必須です");
  });

  it("returns error when email format is invalid", () => {
    const result = validateFormInput({
      name: "Taro",
      email: "not-an-email",
      body: "Message",
    });
    expect(result.valid).toBe(false);
    expect(result.errors).toContain("メールアドレスの形式が正しくありません");
  });

  it("returns error when body is empty", () => {
    const result = validateFormInput({
      name: "Taro",
      email: "taro@example.com",
      body: "",
    });
    expect(result.valid).toBe(false);
    expect(result.errors).toContain("お問い合わせ内容は必須です");
  });

  it("returns multiple errors when multiple fields are invalid", () => {
    const result = validateFormInput({
      name: "",
      email: "",
      body: "",
    });
    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(3);
  });

  it("trims whitespace from inputs", () => {
    const result = validateFormInput({
      name: "  Taro  ",
      email: "  taro@example.com  ",
      body: "  Message  ",
    });
    expect(result.valid).toBe(true);
  });
});
```

- [ ] **Step 2: テスト実行 — 失敗を確認**

```bash
pnpm run test -- test/form-validator.test.ts
```

Expected: FAIL

- [ ] **Step 3: コミット**

```bash
git add test/form-validator.test.ts
git commit -m "test: add form-validator test cases (RED)"
```

---

### Task 15: form-validator.ts — 実装（GREEN）

**Files:**
- Create: `src/form-validator.ts`

- [ ] **Step 1: form-validator.ts を実装**

```typescript
export interface FormInput {
  readonly name: string;
  readonly email: string;
  readonly body: string;
}

export interface ValidationResult {
  readonly valid: boolean;
  readonly errors: readonly string[];
}

const EMAIL_PATTERN =
  /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$/;

export function validateFormInput(input: FormInput): ValidationResult {
  const errors: string[] = [];
  const name = input.name.trim();
  const email = input.email.trim();
  const body = input.body.trim();

  if (name === "") {
    errors.push("名前は必須です");
  }

  if (email === "") {
    errors.push("メールアドレスは必須です");
  } else if (!EMAIL_PATTERN.test(email)) {
    errors.push("メールアドレスの形式が正しくありません");
  }

  if (body === "") {
    errors.push("お問い合わせ内容は必須です");
  }

  return { valid: errors.length === 0, errors };
}
```

- [ ] **Step 2: テスト実行 — 成功を確認**

```bash
pnpm run test -- test/form-validator.test.ts
```

Expected: PASS

- [ ] **Step 3: コミット**

```bash
git add src/form-validator.ts
git commit -m "feat: implement form input validation (GREEN)"
```

---

### Task 16: mail-builder.ts — テスト作成（RED）

**Files:**
- Create: `test/mail-builder.test.ts`

- [ ] **Step 1: テストファイルを作成**

```typescript
import { buildMailOptions } from "../src/mail-builder.js";

describe("buildMailOptions", () => {
  const input = {
    name: "Taro Yamada",
    email: "taro@example.com",
    body: "This is a test inquiry.",
  };

  it("sets recipient to the admin email", () => {
    const result = buildMailOptions(input, "admin@example.com");
    expect(result.to).toBe("admin@example.com");
  });

  it("includes sender name in subject", () => {
    const result = buildMailOptions(input, "admin@example.com");
    expect(result.subject).toContain("Taro Yamada");
  });

  it("includes all form fields in HTML body", () => {
    const result = buildMailOptions(input, "admin@example.com");
    expect(result.htmlBody).toContain("Taro Yamada");
    expect(result.htmlBody).toContain("taro@example.com");
    expect(result.htmlBody).toContain("This is a test inquiry.");
  });

  it("sets replyTo to sender email", () => {
    const result = buildMailOptions(input, "admin@example.com");
    expect(result.replyTo).toBe("taro@example.com");
  });

  it("converts newlines to <br> in body", () => {
    const multiline = {
      name: "Taro",
      email: "taro@example.com",
      body: "Line 1\nLine 2\nLine 3",
    };
    const result = buildMailOptions(multiline, "admin@example.com");
    expect(result.htmlBody).toContain("Line 1<br>Line 2<br>Line 3");
  });

  it("escapes HTML in user input", () => {
    const malicious = {
      name: '<script>alert("xss")</script>',
      email: "attacker@example.com",
      body: '<img src="x" onerror="alert(1)">',
    };
    const result = buildMailOptions(malicious, "admin@example.com");
    expect(result.htmlBody).not.toContain("<script>");
    expect(result.htmlBody).not.toContain("<img");
    expect(result.htmlBody).toContain("&lt;script&gt;");
  });
});
```

- [ ] **Step 2: テスト実行 — 失敗を確認**

```bash
pnpm run test -- test/mail-builder.test.ts
```

Expected: FAIL

- [ ] **Step 3: コミット**

```bash
git add test/mail-builder.test.ts
git commit -m "test: add mail-builder test cases (RED)"
```

---

### Task 17: mail-builder.ts — 実装（GREEN）

**Files:**
- Create: `src/mail-builder.ts`

- [ ] **Step 1: mail-builder.ts を実装**

```typescript
export interface MailInput {
  readonly name: string;
  readonly email: string;
  readonly body: string;
}

export interface MailOptions {
  readonly to: string;
  readonly subject: string;
  readonly htmlBody: string;
  readonly replyTo: string;
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function buildMailOptions(
  input: MailInput,
  adminEmail: string,
): MailOptions {
  const name = escapeHtml(input.name.trim());
  const email = input.email.trim();
  const body = escapeHtml(input.body.trim());

  return {
    to: adminEmail,
    subject: `お問い合わせ: ${input.name.trim()}`,
    htmlBody: [
      "<h2>お問い合わせがありました</h2>",
      `<p><strong>名前:</strong> ${name}</p>`,
      `<p><strong>メール:</strong> ${escapeHtml(email)}</p>`,
      `<p><strong>内容:</strong></p>`,
      `<p>${body.replace(/\n/g, "<br>")}</p>`,
    ].join("\n"),
    replyTo: email,
  };
}
```

- [ ] **Step 2: テスト実行 — 成功を確認**

```bash
pnpm run test
```

Expected: PASS, coverage 80%+

- [ ] **Step 3: コミット**

```bash
git add src/mail-builder.ts
git commit -m "feat: implement mail options builder (GREEN)"
```

---

### Task 18: HTML ファイル作成

**Files:**
- Modify: `src/form.html` (renamed from `src/app.html`)
- Create: `src/result.html`

- [ ] **Step 1: src/form.html を書き換え**

`google.script.run` を使った AJAX パターンで実装（GAS scriptlet タグ `<?= ?>` を HTML 属性内で使うと HTMLHint の `attr-unsafe-chars` ルールに抵触するため）:

```html
<!doctype html>
<html lang="ja">
  <head>
    <base target="_top" />
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      body {
        font-family: sans-serif;
        max-width: 600px;
        margin: 40px auto;
        padding: 0 16px;
      }

      .form-group {
        margin-bottom: 16px;
      }

      label {
        display: block;
        margin-bottom: 4px;
        font-weight: bold;
      }

      input,
      textarea {
        width: 100%;
        padding: 8px;
        border: 1px solid #ccc;
        border-radius: 4px;
        box-sizing: border-box;
      }

      textarea {
        height: 120px;
        resize: vertical;
      }

      button {
        padding: 10px 24px;
        background: #1a73e8;
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;
      }

      button:disabled {
        background: #ccc;
        cursor: not-allowed;
      }

      button:hover:not(:disabled) {
        background: #1557b0;
      }

      .result {
        padding: 16px;
        border-radius: 8px;
        margin-top: 16px;
        display: none;
      }

      .success {
        background: #e6f4ea;
        color: #1e7e34;
      }

      .error {
        background: #fce8e6;
        color: #c5221f;
      }
    </style>
  </head>
  <body>
    <h1>お問い合わせ</h1>
    <form id="contact-form">
      <div class="form-group">
        <label for="name">名前</label>
        <input type="text" id="name" name="name" required />
      </div>
      <div class="form-group">
        <label for="email">メールアドレス</label>
        <input type="email" id="email" name="email" required />
      </div>
      <div class="form-group">
        <label for="body">お問い合わせ内容</label>
        <textarea id="body" name="body" required></textarea>
      </div>
      <button type="submit" id="submit-btn">送信</button>
    </form>
    <div id="result" class="result"></div>

    <script>
      document
        .getElementById("contact-form")
        .addEventListener("submit", function (e) {
          e.preventDefault();
          var btn = document.getElementById("submit-btn");
          btn.disabled = true;
          btn.textContent = "送信中...";
          var formData = {
            name: document.getElementById("name").value,
            email: document.getElementById("email").value,
            body: document.getElementById("body").value,
          };
          google.script.run
            .withSuccessHandler(function (res) {
              var el = document.getElementById("result");
              el.className = "result " + res.status;
              el.textContent = res.message;
              el.style.display = "block";
              btn.disabled = false;
              btn.textContent = "送信";
              if (res.status === "success") {
                document.getElementById("contact-form").reset();
              }
            })
            .withFailureHandler(function (err) {
              var el = document.getElementById("result");
              el.className = "result error";
              el.textContent = "エラーが発生しました: " + err.message;
              el.style.display = "block";
              btn.disabled = false;
              btn.textContent = "送信";
            })
            .submitForm(formData);
        });
    </script>
  </body>
</html>
```

注意: `result.html` は不要になる（結果表示は form.html 内の `#result` div で行う）

- [ ] **Step 2: lint チェック**

```bash
pnpm run lint:css && pnpm run lint:html
```

Expected: PASS

- [ ] **Step 3: コミット**

```bash
git add src/form.html
git commit -m "feat: add contact form HTML template"
```

---

### Task 19: index.ts — GAS エントリポイント

**Files:**
- Modify: `src/index.ts`

- [ ] **Step 1: src/index.ts を書き換え**

```typescript
import { validateFormInput } from "./form-validator.js";
import { buildMailOptions } from "./mail-builder.js";

interface SubmitResult {
  readonly status: "success" | "error";
  readonly message: string;
}

const ADMIN_EMAIL = "admin@example.com";

function doGet(): GoogleAppsScript.HTML.HtmlOutput {
  return HtmlService.createHtmlOutputFromFile("form")
    .setTitle("お問い合わせ")
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function submitForm(formData: {
  name: string;
  email: string;
  body: string;
}): SubmitResult {
  const validation = validateFormInput(formData);

  if (!validation.valid) {
    return { status: "error", message: validation.errors.join("、") };
  }

  const mailOptions = buildMailOptions(formData, ADMIN_EMAIL);
  GmailApp.sendEmail(mailOptions.to, mailOptions.subject, "", {
    htmlBody: mailOptions.htmlBody,
    replyTo: mailOptions.replyTo,
  });

  return {
    status: "success",
    message: "お問い合わせを送信しました。ありがとうございます。",
  };
}
```

注意: `doGet` は `createHtmlOutputFromFile` を使用（テンプレート変数不要のため `createTemplateFromFile` ではない）。`submitForm` は `google.script.run` から呼ばれ、JSON オブジェクトを返す。

- [ ] **Step 2: 全チェック実行**

```bash
pnpm run check
```

Expected: PASS

- [ ] **Step 3: ビルド確認**

```bash
pnpm run build
ls dist/
```

Expected: `index.js`, `appsscript.json`, `form.html`

- [ ] **Step 4: コミット**

```bash
git add src/index.ts
git commit -m "feat: add GAS entry points for form mailer"
```

---

### Task 20: README.md 更新と最終確認

- [ ] **Step 1: README.md を書き換え**

プロジェクト概要、Web App の公開手順、`ADMIN_EMAIL` の変更方法を記載。

- [ ] **Step 2: 最終チェック**

```bash
pnpm run check && pnpm run build
```

Expected: PASS

- [ ] **Step 3: コミット & プッシュ**

```bash
git add README.md
git commit -m "docs: add project README"
git push origin main
```
