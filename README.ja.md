# Apps Script Fleet

[![CI](https://github.com/h13/apps-script-fleet/actions/workflows/ci.yml/badge.svg)](https://github.com/h13/apps-script-fleet/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/h13/apps-script-fleet/blob/main/LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D24-green.svg)](https://nodejs.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-blue.svg)](https://www.typescriptlang.org/)
[![Google Apps Script](https://img.shields.io/badge/Google%20Apps%20Script-Template-4285F4.svg)](https://developers.google.com/apps-script)

[English](README.md)

**Google Apps Script を組織全体でスケールさせるためのインフラ。**

既存の GAS テンプレートは「1 つのプロジェクトをモダンに開発する方法」を提供します。Apps Script Fleet はその先にある問題を解決します — このテンプレートからリポジトリを作成して Script ID を設定すれば、CI/CD パイプラインがすでに動いている状態でスタートできます。GitHub でも GitLab でも、クラウドでも Self-Managed でも動作します。

**[→ クイックスタート](#クイックスタート)** · [含まれるもの](#含まれるもの) · [他のテンプレートとの違い](#他のテンプレートとの違い) · [FAQ](#faq)

## 課題

GAS プロジェクトは小さく始まりますが、増殖します。Slack 通知、レポート自動生成、フォーム処理、Drive のファイル整理 — 気づけば組織に十数個のスクリプトが存在しています。それぞれに必要なもの：

- TypeScript の設定
- バンドラ（Rollup, Webpack, Vite）
- リント・フォーマッタ
- テスト環境とカバレッジ設定
- dev / prod の CI/CD ワークフロー
- clasp の認証管理
- 依存関係の継続的な更新

1 プロジェクトあたりのセットアップに 2〜4 時間。10 プロジェクトなら丸 1 週間がボイラープレートに消えます。さらにその後も、10 個の異なる設定を個別にメンテナンスし続けることになります。

## 解決策：1 リポ = 1 機能

![アーキテクチャ — 1 リポ 1 機能 + 共有インフラ](docs/architecture.png)

Apps Script Fleet は各 GAS 機能を独立したリポジトリとして扱い、組織レベルの共有インフラで支えます：

- **初回のみの設定**: `CLASPRC_JSON` を組織/グループレベルのシークレットに追加（[GitHub](https://docs.github.com/ja/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-an-organization) または [GitLab](https://docs.gitlab.com/ci/variables/#for-a-group)）。このテンプレートから作成されたすべてのリポが自動的に利用します。
- **プロジェクトごとの設定（約 5 分）**: テンプレートからリポを作成 → Script ID を設定 → 完了。PR/MR で CI が走り、マージで本番デプロイ。
- **一括メンテナンス**: [Renovate](https://docs.renovatebot.com/) が全リポの依存関係を自動更新。[Template Sync](.github/workflows/sync-template.yml) がツーリングの改善を上流テンプレートから自動伝播。

違いを一目で：

![Before / After 比較](docs/before-after.png)

## 含まれるもの

| カテゴリ   | ツール                                                 |
| ---------- | ------------------------------------------------------ |
| 言語       | TypeScript（strict モード）                            |
| バンドラ   | Rollup（GAS 互換出力）                                 |
| デプロイ   | clasp（dev / prod 環境）                               |
| テスト     | Jest（カバレッジ閾値 80%）                             |
| リント     | ESLint, Prettier, Stylelint, HTMLHint                  |
| Git フック | husky + lint-staged                                    |
| CI/CD      | GitHub Actions + GitLab CI（PR で CI、マージで CD）    |
| 依存管理   | Renovate（自動更新 + オートマージ）                    |
| 同期       | Template Sync ワークフロー（上流の設定変更を自動反映） |

その結果 — 開発者の1日はこう変わります：

![開発者の1日：Apps Script Fleet なし vs あり](docs/before-after-human.png)

## 他のテンプレートとの違い

|                    | [Apps Script Engine](https://github.com/WildH0g/apps-script-engine-template) | Apps Script Fleet                                |
| ------------------ | ---------------------------------------------------------------------------- | ------------------------------------------------ |
| 設計思想           | 機能豊富な DX                                                                | 最小限の制約                                     |
| 最適な用途         | 単一の複雑なプロジェクト                                                     | 多数の小さな自動化                               |
| フロントエンド開発 | Vite + Alpine.js + Tailwind                                                  | 基本的な HTML（GAS 組み込み）                    |
| テスト             | Vitest（任意）                                                               | Jest（80% カバレッジ必須）                       |
| テンプレート同期   | —                                                                            | 週次（自動 PR）                                  |
| 組織レベルの認証   | —                                                                            | CLASPRC_JSON 共有シークレット（GitHub + GitLab） |

> リッチな UI をクライアントサイドフレームワークで構築する場合は、[Apps Script Engine](https://github.com/WildH0g/apps-script-engine-template) が適しています。
> 組織全体で 5 つ以上の小さな GAS 自動化を管理する場合は、Apps Script Fleet の出番です。

## 組織セットアップ（初回のみ）

チームが Apps Script Fleet を使い始める前に、組織の管理者が clasp の共有認証情報をセットアップします：

1. **clasp にログイン**（CI/CD デプロイに使う Google アカウントで）：

   ```bash
   npx @google/clasp login
   ```

   `~/.clasprc.json` が生成されます。

2. **組織のパスワードマネージャーに保存** — `~/.clasprc.json` の内容を共有クレデンシャルとして登録します（例: 「clasp CI/CD — GAS Fleet」）。

3. **`CLASPRC_JSON` を組織レベルの CI/CD シークレットに設定**：
   - **GitHub**: [Organization secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-an-organization) → `CLASPRC_JSON` を追加（値は JSON 全体）
   - **GitLab**: グループ → Settings → CI/CD → Variables → `CLASPRC_JSON` を追加（protected, masked）

4. **各開発者**はパスワードマネージャーから `~/.clasprc.json` をローカルマシンにコピーします。

### GCP プロジェクトの設定（任意、推奨）

全 GAS プロジェクトを 1 つの標準 GCP プロジェクトに紐付けることで、Cloud Logging / Error Reporting / API 使用量の一元管理と、CI/CD からの `clasp run` による Script Properties 自動注入が可能になります。

**前提条件：**

1. **標準 GCP プロジェクトを作成**（または既存のものを使用）: [Google Cloud Console](https://console.cloud.google.com/)
2. **Apps Script API を有効化**: [API とサービス → API を有効化](https://console.cloud.google.com/apis/library/script.googleapis.com)
3. **OAuth 同意画面を設定**: [API とサービス → OAuth 同意画面](https://console.cloud.google.com/apis/credentials/consent) — Workspace 組織は「内部」を選択
4. **プロジェクト番号を確認**（プロジェクト ID ではなく番号）: [プロジェクト設定](https://console.cloud.google.com/iam-admin/settings) → プロジェクト番号
5. **`GCP_PROJECT_NUMBER` を組織レベルの CI/CD 変数に設定**：
   - **GitHub**: Organization variable → `GCP_PROJECT_NUMBER`
   - **GitLab**: グループ → Settings → CI/CD → Variables → `GCP_PROJECT_NUMBER`

### プロジェクトごとの初期化

`~/.clasprc.json` がローカルにある状態で、init スクリプトを実行すると GAS プロジェクトの作成と CI/CD 変数の設定を自動で行います：

```bash
# GitHub: gh CLI で認証済みであること
./scripts/init.sh --title "My Script" --gcp-project 123456789

# GitLab: GITLAB_TOKEN を設定してから実行
GITLAB_TOKEN="glpat-xxx" ./scripts/init.sh --title "My Script" --gcp-project 123456789
```

オプション：

- `--title "名前"` — GAS プロジェクト名（デフォルト: ディレクトリ名）
- `--type standalone|sheets|docs|slides|forms` — GAS プロジェクトタイプ（デフォルト: `standalone`）
- `--gcp-project <番号>` — 紐付ける GCP プロジェクト番号（Cloud Logging + `clasp run` が有効に）

スクリプトは dev/prod の GAS プロジェクトを作成し、初回デプロイを行い、`CLASP_JSON` + `DEPLOYMENT_ID` を CI/CD プラットフォームに設定します。`--gcp-project` を指定した場合、GAS プロジェクトが GCP プロジェクトに紐付けられ、`GCP_PROJECT_NUMBER` が CI/CD 変数として設定されます。

### CI/CD 経由の Script Properties 注入

GCP プロジェクト統合が設定されている場合、デプロイ時に Script Properties を自動注入できます：

1. **`SCRIPT_PROPERTIES`** を CI/CD シークレットとして設定（環境ごとの JSON 文字列）：
   ```json
   {"API_KEY":"xxx","SLACK_WEBHOOK":"https://hooks.slack.com/..."}
   ```
2. `GCP_PROJECT_NUMBER` と `SCRIPT_PROPERTIES` の両方が設定されている場合、`clasp deploy` 後に自動的にプロパティが注入されます
3. hook ベースの代替方法は `.github/hooks/post-deploy.sh.example` または `.gitlab/post-deploy.yml.example` を参照

## クイックスタート

- **GitHub / GitHub Enterprise Server**: [docs/setup-github.ja.md](docs/setup-github.ja.md)
- **GitLab.com / GitLab Self-Managed**: [docs/setup-gitlab.ja.md](docs/setup-gitlab.ja.md)

## CI/CD パイプライン

GitHub Actions と GitLab CI の両方の設定が含まれています。push 先のプラットフォームで同じパイプラインが動きます。CI/CD 変数の設定以外の追加セットアップは不要です。

### GitHub Actions

```
Push / PR  →  CI (ci.yml)  →  CD (cd.yml)
               ├── Lint          └── Build
               ├── Typecheck         └── clasp push
               ├── Test                  └── clasp deploy
               └── Build
```

| トリガー            | パイプライン   | 動作                                         |
| ------------------- | -------------- | -------------------------------------------- |
| `main` への PR      | CI のみ        | lint → typecheck → test → build              |
| `dev` へのプッシュ  | CI → CD (dev)  | cancel-in-progress（後続が先行をキャンセル） |
| `main` へのプッシュ | CI → CD (prod) | queued（順次実行、スキップなし）             |

### GitLab CI

`.gitlab-ci.yml` は `.gitlab/` 内の分割設定ファイル（ci.yml, cd.yml, sync-template.yml）をインクルードします。変数設定や Self-Managed runner の要件は [docs/setup-gitlab.ja.md](docs/setup-gitlab.ja.md) を参照してください。

| ジョブ          | ステージ | トリガー            |
| --------------- | -------- | ------------------- |
| `check`         | check    | push / MR           |
| `deploy_dev`    | deploy   | `dev` への push     |
| `deploy_prod`   | deploy   | `main` への push    |
| `template_sync` | sync     | スケジュール / 手動 |

### Pre/Post-Deploy フック

テンプレート管理ファイルを変更せずにデプロイパイプラインをカスタマイズ：

- **GitHub Actions**: `.github/hooks/pre-deploy.sh` または `.github/hooks/post-deploy.sh` を作成
- **GitLab CI**: `.gitlab/pre-deploy.yml` または `.gitlab/post-deploy.yml` を作成

これらのファイルはテンプレートからの同期対象外です。

## プロジェクト構成

```
your-project/
├── src/
│   ├── index.ts           # GAS エントリポイント（doGet 等）
│   ├── greeting.ts        # ビジネスロジック（サンプル）
│   └── app.html           # Web UI（サンプル）
├── test/
│   └── greeting.test.ts
├── .github/workflows/
│   ├── ci.yml             # CI: lint → typecheck → test → build
│   ├── cd.yml             # CD: CI 成功後にデプロイ
│   └── sync-template.yml  # 上流テンプレートとの同期
├── .gitlab-ci.yml         # GitLab CI/CD ルート（.gitlab/*.yml をインクルード）
├── .gitlab/
│   ├── ci.yml             # CI: lint → typecheck → test → build
│   ├── cd.yml             # CD: clasp push + deploy
│   └── sync-template.yml  # テンプレート同期（スケジュール実行）
├── rollup.config.mjs
├── tsconfig.json
├── jest.config.json
├── eslint.config.mjs
├── renovate.json          # 自動更新設定
└── .templatesyncignore    # プロジェクト固有のコードは上書きされない
```

## 開発ワークフロー

### 日常の開発

```
# src/ を編集 → チェック → dev にデプロイ → 動作確認
pnpm run check
pnpm run deploy
```

### PR フロー

1. feature ブランチを作成
2. コミット — husky が lint-staged を自動実行
3. プッシュして PR を作成 — CI が自動実行
4. `main` にマージ — CD が本番にデプロイ

### 利用可能なコマンド

| コマンド                   | 説明                                                |
| -------------------------- | --------------------------------------------------- |
| `pnpm run check`           | lint + lint:css + lint:html + 型チェック + テスト   |
| `pnpm run build`           | TypeScript をバンドル + アセットを `dist/` にコピー |
| `pnpm run deploy`          | check → build → dev にデプロイ                      |
| `pnpm run deploy:prod`     | check → build → 本番にデプロイ                      |
| `pnpm run test -- --watch` | Jest のウォッチモード                               |

## リポジトリの同期

### Template Sync

- **GitHub**: `sync-template.yml` ワークフローが週次で上流テンプレートの更新をチェック。更新がある場合、`template-sync` ラベル付きの PR が自動作成されます。
- **GitLab**: Group 内に Template Project を作成し、「Create from template」で各 GAS プロジェクトを作成。User Project は `TEMPLATE_REPO_URL`（Group Variable）経由で Template Project から同期します。詳細は [docs/setup-gitlab.ja.md](docs/setup-gitlab.ja.md) を参照。

`.templatesyncignore` はホワイトリスト形式を採用しています — `:!` プレフィックス付きのファイルのみが同期対象です。プロジェクト固有のファイル（`src/`, `test/`, `README.md` 等）は自動的に除外されます。

### Renovate

[`h13/renovate-config:node`](https://github.com/h13/renovate-config) の共有プリセットで設定：

- minor / patch: オートマージ
- major: 手動レビュー用の PR を作成（`breaking` ラベル付き）
- devDependencies: グループ化してオートマージ
- リリースから 7 日間の安定性バッファ
- 毎週日曜 21 時以降に実行

## カスタマイズ

### OAuth スコープの追加

デフォルトでは `appsscript.json` に `oauthScopes` フィールドは含まれていません。これにより、Apps Script が実行時に必要最小限のスコープを自動推論するため、個人 Google アカウントでの OAuth 同意画面ブロックを回避できます（一般ユーザーアカウントは Google の [OAuth アプリ確認要件](https://support.google.com/cloud/answer/9110914) の対象であり、明示的なスコープは「確認されていないアプリ」警告を発生させることがあります）。

プロジェクトで特定のスコープが必要な場合（例: `UrlFetchApp`、スプレッドシート、Drive）、`appsscript.json` に `oauthScopes` フィールドを追加してください：

```json
{
  "oauthScopes": [
    "https://www.googleapis.com/auth/script.external_request",
    "https://www.googleapis.com/auth/spreadsheets"
  ]
}
```

> **注意**: `oauthScopes` を宣言すると、Apps Script はスコープの自動推論を停止します。プロジェクトが必要とするすべてのスコープを明示的にリストする必要があります。

### ソースファイルの追加

1. `src/` にモジュールを作成（例: `src/utils.ts`）
2. `src/index.ts` でインポート — Rollup がすべてをバンドル
3. `test/` にテストを追加

> GAS から呼び出せるのは `src/index.ts` のトップレベルに定義された関数のみです。

### カバレッジ閾値の調整

`jest.config.json` の `coverageThreshold` を編集。デフォルトは全メトリクス 80% です。スコープの小さなプロジェクト（関数 5〜10 個）では 100% への引き上げを推奨します。

### Web App の設定

プロジェクトで `doGet` や `doPost` を Web App として使用する場合、`appsscript.json` に `webapp` セクションを追加してください：

```json
{
  "webapp": {
    "access": "ANYONE",
    "executeAs": "USER_ACCESSING"
  }
}
```

| プロパティ  | 選択肢                                           |
| ----------- | ------------------------------------------------ |
| `access`    | `MYSELF`, `DOMAIN`, `ANYONE`, `ANYONE_ANONYMOUS` |
| `executeAs` | `USER_ACCESSING`, `USER_DEPLOYING`               |

詳細は[公式ドキュメント](https://developers.google.com/apps-script/manifest/web-app)を参照してください。

## テスト

テストは `test/` に配置し、Jest で実行します。`src/index.ts` はカバレッジ対象外です（`HtmlService` 等の GAS グローバルは Node.js で実行できないため）。

```
pnpm run test              # カバレッジ付きで実行
pnpm run test -- --watch   # ウォッチモード
```

## Example プロジェクト

Apps Script Fleet で構築された実プロジェクト:

| プロジェクト                                                                        | パターン     | 説明                                                                             |
| ----------------------------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------- |
| [custom-functions](https://github.com/h13/apps-script-custom-functions)             | カスタム関数 | Google Sheets データ検証（メール、電話番号、郵便番号）                           |
| [form-mailer](https://github.com/h13/apps-script-form-mailer)                       | Web App      | お問い合わせフォーム + Gmail 通知                                                |
| [slack-channel-archiver](https://github.com/h13/apps-script-slack-channel-archiver) | 時限トリガー | 非アクティブな Slack チャンネルを自動アーカイブ（パブリック + プライベート対応） |
| [slack-notifier](https://github.com/h13/apps-script-slack-notifier)                 | 時限トリガー | スプレッドシートの新規行を Slack Bot Token 経由で通知                            |

各リポジトリが「1 リポ = 1 機能」パターンを CI/CD・テスト・デプロイ付きで実演しています。

## FAQ

### なぜモノレポではなく 1 リポ 1 機能？

GAS プロジェクトは基本的に小さく自己完結した自動化です。モノレポはワークスペースツーリングや選択的デプロイなど、このスケールでは割に合わない複雑さを持ち込みます。リポを分けることで、独立した CI/CD、明確なオーナーシップ、シンプルなメンタルモデルが得られます。Template Sync と Renovate がメンテナンスのオーバーヘッドを吸収します。

### なぜデフォルトでカバレッジ 80%？

小さく焦点の絞られた GAS 関数であれば、高いカバレッジは現実的に達成可能で、本番に届く前に微妙なバグを捕捉します。80% は採用障壁を低く保ちつつ、意味のある品質ゲートとして機能します。スコープが小さなプロジェクト（関数 5〜10 個）では、`jest.config.json` で 100% への引き上げを検討してください。

## ライセンス

[MIT](LICENSE)
