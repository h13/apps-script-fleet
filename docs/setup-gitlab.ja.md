# クイックスタート: GitLab（GitLab.com / Self-Managed）

[English](setup-gitlab.md)

## 前提条件

- Node.js >= 24 と pnpm 10
- [mise](https://mise.jdx.dev/) を使っている場合は `mise install` で自動セットアップ
- Docker executor を使用する GitLab Runner（Self-Managed の場合）

## 初回: Group の設定

### 1. CLASPRC_JSON の追加

CI/CD 用の専用 Google アカウント（例: `gas-deploy@yourcompany.com`）を作成し、`clasp login` を実行。`~/.clasprc.json` の内容を **Group CI/CD Variable**（名前: `CLASPRC_JSON`、masked, protected）として追加します。

> Group 内でこのテンプレートから作成されるすべてのプロジェクトがこの変数を共有します。プロジェクトごとの認証設定は不要です。

### 2. Template Project の作成

upstream テンプレートを GitLab Group にインポートします。このプロジェクトが組織内の全 GAS プロジェクトのソースになります。

**方法 A — GitHub からインポート（github.com へのネットワークアクセスが必要）:**

GitLab → New project → Import project → GitHub → `apps-script-fleet` を選択

**方法 B — クローンして push（エアギャップ環境では必須）:**

```
git clone https://github.com/h13/apps-script-fleet.git apps-script-fleet
cd apps-script-fleet
git remote set-url origin https://gitlab.yourcompany.com/<your-group>/apps-script-fleet.git
git push -u origin main
```

次に **[Group project template](https://docs.gitlab.com/user/group/custom_project_templates/)**（Settings → General → Custom project templates）として登録します。これにより Group メンバー全員が「Create from template」で利用できるようになります。

> Instance レベルのテンプレートには管理者権限が必要で、GitLab.com では利用できません。すべての環境で Group テンプレートを推奨します。

### 3. Template Project に Template Sync を設定

Template Project は GitHub から同期して最新の状態を保ちます。この設定は **Template Project にのみ**行います — 個々の GAS プロジェクトには不要です。

1. **Project Access Token** を作成（Settings → Access Tokens、`write_repository` スコープ）
2. CI/CD Variable として `GITLAB_PUSH_TOKEN` の名前で追加
3. `TEMPLATE_PROJECT_PATH` を CI/CD Variable として追加（値は Template Project のパス。例: `your-group/apps-script-fleet`）。これにより Template Project 自体で CD パイプラインが実行されるのを防ぎます。
4. **Pipeline Schedule** を作成（CI/CD → Schedules）— 例: 毎週日曜

**Self-Managed runner から `github.com` に到達できない場合:**

Template Project の **project レベル** CI/CD Variable として `TEMPLATE_REPO_URL` を上書きし、社内ミラーを指定します（例: `https://gitlab.internal/infra/apps-script-fleet.git`）。ミラーは手動、または `github.com` にアクセス**できる** Runner 上のスケジュールジョブで最新に保ちます。

### 4. TEMPLATE_REPO_URL を Group Variable に設定

`TEMPLATE_REPO_URL` を **Group CI/CD Variable** として追加し、Template Project の git URL を指定します：

```
https://gitlab.yourcompany.com/<your-group>/apps-script-fleet.git
```

Group 内のすべての GAS プロジェクトがこの変数を自動的に継承し、GitHub ではなく Template Project から同期するようになります。

> **優先順位の仕組み:** Template Project の project レベル `TEMPLATE_REPO_URL`（GitHub または社内ミラーを指す）が Group Variable より優先されます。これにより、Template Project は GitHub から同期し、User Project は Template Project から同期します。

## プロジェクトごと: 新しい GAS リポジトリの作成

### 1. プロジェクトの作成

GitLab → New project → **Create from template** → `apps-script-fleet` を選択

作成後、ローカルにクローンして依存関係をインストール：

```
git clone https://gitlab.yourcompany.com/<your-group>/<your-project>.git
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

### 3. CI/CD Variables の設定

Settings → CI/CD → Variables で以下を追加：

| 変数            | Environment scope | 値                                        | オプション |
| --------------- | ----------------- | ----------------------------------------- | ---------- |
| `CLASP_JSON`    | `development`     | `{"scriptId":"DEV_ID","rootDir":"dist"}`  | Masked     |
| `CLASP_JSON`    | `production`      | `{"scriptId":"PROD_ID","rootDir":"dist"}` | Masked     |
| `DEPLOYMENT_ID` | `development`     | dev のデプロイメント ID                   |            |
| `DEPLOYMENT_ID` | `production`      | prod のデプロイメント ID                  |            |

> **GCP プロジェクト統合時**: `CLASP_JSON` に `"projectId":"プロジェクト番号"` を追加します（例: `{"scriptId":"...","rootDir":"dist","projectId":"123456789"}`）。`init.sh --gcp-project` 使用時は自動設定されます。

### 4. Template Sync の設定

1. **Project Access Token** を作成（Settings → Access Tokens、`write_repository` スコープ）
2. CI/CD Variable として `GITLAB_PUSH_TOKEN` の名前で追加
3. **Pipeline Schedule** を作成（CI/CD → Schedules）— 例: 毎週日曜

`TEMPLATE_REPO_URL` は Group レベルで設定済みのため、プロジェクトごとの設定は不要です。

### 5. 確認とデプロイ

```
pnpm run check    # lint + 型チェック + テスト
```

`dev` への push で dev 環境へ、`main` への push で本番環境へ、GitLab CI が自動デプロイします。

## ネットワーク要件（Self-Managed）

**User Projects:**

| ジョブ          | 必要な外部通信先                                          |
| --------------- | --------------------------------------------------------- |
| `check`         | npm レジストリのみ（`pnpm install` 用）                   |
| `deploy_*`      | `script.google.com`（HTTPS）                              |
| `template_sync` | Template Project（社内 GitLab、Group Variable 経由）       |

**Template Project:**

| ジョブ          | 必要な外部通信先                                                            |
| --------------- | --------------------------------------------------------------------------- |
| `template_sync` | `github.com`（デフォルト）または社内ミラー（`TEMPLATE_REPO_URL` 上書き時） |

User Project の Runner は `github.com` への接続が不要です。外部アクセス（または社内ミラー）が必要なのは Template Project の Runner のみです。

## 既存環境からの移行

従来のインポート/クローン方式で作成したプロジェクトは影響を受けません。既存の Template Sync 設定はそのまま独立して動作します。新しいモデルへの移行は任意です：

1. `TEMPLATE_REPO_URL` を Group Variable として Template Project を指すように設定
2. プロジェクトごとの `TEMPLATE_REPO_URL` 上書き（ある場合）を削除し、Group Variable を継承
3. プロジェクトごとの `GITLAB_PUSH_TOKEN` と Pipeline Schedule はそのまま
