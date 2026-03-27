# クイックスタート: GitHub

[English](setup-github.md)

## 前提条件

- Node.js >= 24 と pnpm 10
- [mise](https://mise.jdx.dev/) を使っている場合は `mise install` で自動セットアップ
- または [Dev Container / Codespaces](#dev-container--codespaces) でローカル環境構築なしで開始可能

## 初回：Organization の設定

CI/CD 用の専用 Google アカウント（例: `gas-deploy@yourcompany.com`）を作成し、`clasp login` を実行。`~/.clasprc.json` の内容を **Organization Secret**（名前: `CLASPRC_JSON`）として追加します。

> このテンプレートから作成されるすべてのリポジトリがこの Secret を共有します。リポごとの認証設定は不要です。

## プロジェクトごと：新しい GAS リポジトリの作成

### 1. テンプレートから作成

GitHub で **"Use this template"** をクリックし、クローン：

```
git clone https://github.com/<your-org>/<your-project>.git
cd <your-project>
pnpm install
```

### 2. Script ID の設定

`.clasp-dev.json` と `.clasp-prod.json` を作成（gitignore 済み）：

```json
{
  "scriptId": "YOUR_SCRIPT_ID",
  "rootDir": "dist"
}
```

### 3. GitHub Environments の設定

| Environment   | Secret / Variable         | 値                                        |
| ------------- | ------------------------- | ----------------------------------------- |
| `development` | Secret: `CLASP_JSON`      | `{"scriptId":"DEV_ID","rootDir":"dist"}`  |
| `development` | Variable: `DEPLOYMENT_ID` | dev のデプロイメント ID                   |
| `production`  | Secret: `CLASP_JSON`      | `{"scriptId":"PROD_ID","rootDir":"dist"}` |
| `production`  | Variable: `DEPLOYMENT_ID` | prod のデプロイメント ID                  |

> **GCP プロジェクト統合時**: `CLASP_JSON` に `"projectId":"プロジェクト番号"` を追加します（例: `{"scriptId":"...","rootDir":"dist","projectId":"123456789"}`）。`init.sh --gcp-project` 使用時は自動設定されます。

### 4. 確認とデプロイ

```
pnpm run check    # lint + 型チェック + テスト
pnpm run deploy   # check → build → dev にデプロイ
```

これで完了です。`main` へのプッシュで本番デプロイが自動的に実行されます。

## Dev Container / Codespaces

ローカル環境の構築は不要です。`.devcontainer/` にすべて設定済み。

- **VS Code**: 「Reopen in Container」を選択
- **GitHub Codespaces**: Code → Codespaces → Create codespace on main

コンテナ内での `clasp login` は `pnpm exec clasp login --no-localhost` を使用してください。
