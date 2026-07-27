# Secret Manager + Workload Identity Federation による clasp 認証情報管理

[English](secret-manager.md)

フリートの認証情報アーキテクチャの single source of truth です。従来の「org
secret + パスワードマネージャー」による `CLASPRC_JSON` 配布を置き換えます。

## アーキテクチャ

**clasp の認証そのものは変わりません。** clasp は今後も `clasp login` が生成する
`~/.clasprc.json`(ユーザー OAuth リフレッシュトークン)を使います — Apps
Script API はスクリプトの push/deploy にサービスアカウントを許可していないため、
GCP ネイティブ認証への置き換えは不可能です。変わるのはトークンの**保管場所**
(Secret Manager)と**配送経路**(CI は WIF、開発者は個人 gcloud)だけです。

認証は二段構えになります:

1. **Secret Manager から `.clasprc.json` を取り出すための認証** — WIF(CI)/
   個人 gcloud(開発者)。IAM によるスコープ制御・監査ログ・ローテーションが
   効くのはこの層です。
2. **clasp が GAS へデプロイするための認証** — 取り出した `.clasprc.json`
   (従来どおり・据え置き)。

すべて中央集約されており、**リポ単位のセットアップ作業はゼロ**です:

| リソース | 個数 | スコープ |
| --- | --- | --- |
| Secret `clasp-credentials` | 1 | 中央 GCP プロジェクト。CI は常に `latest` を読む |
| WIF プール `gas-fleet` | 1 | 配下にプロバイダ `github` + `gitlab` |
| IAM バインディング | org/group 単位 | `principalSet://…/attribute.repository_owner/<org>`(GitHub)/ `attribute.namespace_path/<group>`(GitLab) |
| CI 変数 `GCP_WIF_PROVIDER`, `CLASPRC_SECRET` | org/group レベル | 全リポに自動継承 |

**直接 WIF(サービスアカウント偽装なし)** を採用しています。Secret Manager は
フェデレーテッドトークンを直接受け付けるため、プールの `principalSet://` に
`roles/secretmanager.secretAccessor` を直付与でき、中間サービスアカウントが
不要です。監査ログにはアクセスごとに `attribute.repository` / `project_path`
が記録されます。

### デュアルモード規則(両 CI プラットフォーム共通)

- `GCP_WIF_PROVIDER` が設定済み → Secret Manager 経路。取得失敗は**ジョブ失敗**
  — legacy secret へのサイレントフォールバックはしません。
- `GCP_WIF_PROVIDER` 未設定 → legacy `CLASPRC_JSON`(エアギャップ GitLab 用に
  存続)。
- どちらも無し → 明示エラー。

## 一度きりの組織セットアップ

コマンドはすべて中央 GCP プロジェクト(Cloud Logging / `clasp run` と同じもの)
に対して実行します。課金の有効化が前提です。

```bash
PROJECT_ID=your-central-project        # 英数字のプロジェクト ID
ORG=your-github-org                    # GitHub organization
GROUP=your-gitlab-group                # GitLab トップレベルグループ
GITLAB_URL=https://gitlab.example.com  # または https://gitlab.com
gcloud config set project "$PROJECT_ID"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# 0. API の有効化
gcloud services enable secretmanager.googleapis.com sts.googleapis.com iam.googleapis.com
```

### 1. secret の作成

デプロイ専用 Google アカウント(例: `gas-deploy@yourcompany.com`)で:

```bash
npx @google/clasp login            # ~/.clasprc.json を生成
gcloud secrets create clasp-credentials --replication-policy=automatic
gcloud secrets versions add clasp-credentials --data-file="$HOME/.clasprc.json"
```

### 2. WIF プールの作成

```bash
gcloud iam workload-identity-pools create gas-fleet \
  --location=global --display-name="GAS Fleet CI"
```

### 3a. GitHub プロバイダ

attribute condition は**必須**です: `token.actions.githubusercontent.com` は
全 GitHub org が共有するマルチテナント issuer のためです。

```bash
gcloud iam workload-identity-pools providers create-oidc github \
  --location=global --workload-identity-pool=gas-fleet \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${ORG}'"
```

### 3b. GitLab プロバイダ

```bash
gcloud iam workload-identity-pools providers create-oidc gitlab \
  --location=global --workload-identity-pool=gas-fleet \
  --issuer-uri="${GITLAB_URL}" \
  --allowed-audiences="${GITLAB_URL}" \
  --attribute-mapping="google.subject=assertion.sub,attribute.project_path=assertion.project_path,attribute.namespace_path=assertion.namespace_path" \
  --attribute-condition="assertion.namespace_path == '${GROUP}' || assertion.namespace_path.startsWith('${GROUP}/')"
```

`--allowed-audiences` は CI の JWT の `aud` と一致する必要があります。テンプレは
`$CI_SERVER_URL`(スキーム込み・末尾スラッシュ無し)を設定します。

### 4. CI へのアクセス付与(org/group 単位)

```bash
POOL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/gas-fleet"

gcloud secrets add-iam-policy-binding clasp-credentials \
  --role=roles/secretmanager.secretAccessor \
  --member="principalSet://iam.googleapis.com/${POOL}/attribute.repository_owner/${ORG}"

gcloud secrets add-iam-policy-binding clasp-credentials \
  --role=roles/secretmanager.secretAccessor \
  --member="principalSet://iam.googleapis.com/${POOL}/attribute.namespace_path/${GROUP}"
```

### 5. 開発者へのアクセス付与

```bash
gcloud secrets add-iam-policy-binding clasp-credentials \
  --role=roles/secretmanager.secretAccessor \
  --member="group:gas-developers@yourcompany.com"
```

### 6. Data Access 監査ログの有効化

**デフォルト OFF・課金対象**です — アクセス単位の監査証跡が必要なら必須。
[IAM → 監査ログ](https://console.cloud.google.com/iam-admin/audit)で
**Secret Manager API** の **Data Read** を有効化するか、ポリシーで:

```yaml
# gcloud projects get-iam-policy $PROJECT_ID > policy.yaml に追記して set-iam-policy
auditConfigs:
  - service: secretmanager.googleapis.com
    auditLogConfigs:
      - logType: DATA_READ
```

以後、すべての `AccessSecretVersion` がフェデレーテッドプリンシパル付きで
Cloud Logging に記録されます — `attribute.repository`(GitHub)/
`project_path`(GitLab)を含むため、org 一括付与のままでもリポ単位で追跡
できます。

### 7. CI 変数の設定(org/group レベル、両プラットフォーム同名)

| 変数 | 値 |
| --- | --- |
| `GCP_WIF_PROVIDER` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/gas-fleet/providers/github`(GitHub)/ `…/providers/gitlab`(GitLab) |
| `CLASPRC_SECRET` | `projects/<PROJECT_ID>/secrets/clasp-credentials` |

- **GitHub**: Organization → Settings → Actions → Variables(secret ではなく
  variable — 秘密情報ではないため)。
- **GitLab**: Group → Settings → CI/CD → Variables。**unprotected** で設定して
  ください: protected にすると `dev` パイプラインから見えず、dev デプロイが
  気づかないうちに legacy モードに落ちます。

## 開発者のアクセス

```bash
gcloud auth login          # 個人アカウント、マシンごとに1回
./scripts/fetch-clasp-credentials.sh
```

- `~/.clasprc.json` は `$HOME` 配置なので、1回の取得で**マシン上の全リポ**を
  カバーします。
- スクリプトは冪等です: ファイルが存在すれば `--force` なしでは何もしません
  (ローテーション後は `--force` で再取得)。
- GCP プロジェクトは `--project` → `$CLASP_SECRET_PROJECT` →
  `.clasp-dev.json` / `.clasp.json` の `projectId` の順で解決されます。
- オフボーディング = Google グループから外すだけ。次のローテーション後は
  手元のコピーも無効になります。

## ローテーション

旧方式では不可能でしたが、今後は定常運用です:

1. デプロイ用アカウントで再度 `clasp login` →
   `gcloud secrets versions add clasp-credentials --data-file="$HOME/.clasprc.json"`。
   CI は `latest` 参照なので即時反映 — リポ側の作業はゼロ。
2. 任意リポの dev デプロイで検証。
3. `gcloud secrets versions disable <old>` → 猶予期間の後
   `gcloud secrets versions destroy <old>`。
4. 開発者は `./scripts/fetch-clasp-credentials.sh --force` で再取得。

## 既存フリートの CLASPRC_JSON からの移行

1. 上記の一度きりのセットアップ(CI 変数含む)を完了する。旧 `cd.yml` は未知の
   変数を無視するため、先行設定は無害です。
2. template-sync の PR/MR で新しい `cd.yml` + スクリプトが行き渡るのを待つ
   (または手動 sync)。
3. 数リポで WIF 経由のデプロイを確認 — Audit Logs にフェデレーテッド
   プリンシパル付きの `AccessSecretVersion` が出ること。
4. org secret / group variable の `CLASPRC_JSON` とパスワードマネージャーの
   エントリを削除。`publish.yml` の `secrets: inherit` による露出も同時に
   消滅します。

## ハードニング: リポ単位付与(オプション)

org/group 一括の `principalSet` の代わりに、リポ単位で付与できます:

```bash
# GitHub — 特定リポのみ
--member="principalSet://iam.googleapis.com/${POOL}/attribute.repository/${ORG}/critical-repo"
# GitLab — 特定プロジェクトのみ
--member="principalSet://iam.googleapis.com/${POOL}/attribute.project_path/${GROUP}/critical-repo"
```

トレードオフ: 新リポごとに明示的な IAM 付与が必要になります。GitHub では
`sub = repo:ORG/REPO:environment:production` で deployment environment に
ピン留めもできますが、このテンプレは `workflow_run` トリガーでデプロイするため
`ref` ベースの条件は不安定です — `repository` / `environment` クレームを
使ってください。

## スコープの限界(既知の制約)

取り出した `.clasprc.json` は依然としてフリート内の**すべての** GAS プロジェクト
を操作できるユーザー OAuth トークンです。この移行で改善されるのは配布・保管・
失効・監査であり、トークン自体の爆発半径ではありません(Apps Script API の
制約上、不可避です)。

## トラブルシューティング

| 症状 | 原因の見立て |
| --- | --- |
| STS 403 `unable to acquire impersonated credentials` / `The given credential is rejected by the attribute condition` | プロバイダの `--attribute-condition` 不一致(org/group 違い)、または JWT の `aud` が `--allowed-audiences` と不一致。JWT の `aud` = `$CI_SERVER_URL`(スキーム込み・末尾スラッシュ無し)。 |
| STS 400 `Invalid value for "audience"` | STS リクエストの `audience` は `//iam.googleapis.com/projects/<NUM>/…/providers/<name>` — **`https:` プレフィックス無し**、プロジェクト**番号**を使う。 |
| STS 400 `mapped attribute google.subject exceeds the 127 bytes limit` | JWT の `sub` が長すぎる(深くネストした GitLab group、長い GitHub repo/environment 名)。`google.subject` を短いクレームに再マップする(例: GitLab は `assertion.project_path`)— IAM は attribute にバインドしているため他は変更不要。 |
| Secret Manager 403 `PERMISSION_DENIED`(CI) | `principalSet` バインディングの欠落・誤り。attribute 名(`repository_owner` / `namespace_path`)と値を確認。 |
| `PERMISSION_DENIED`(開発者) | 開発者 Google グループに未所属、またはグループに `secretAccessor` が無い。 |
| GitLab ジョブが script 前に `id_tokens` エラーで失敗 | GitLab < 16.1(`aud` の変数展開)または < 15.7(`id_tokens` 自体)。アップグレードするか、旧テンプレ + legacy モードを継続。 |
| GitLab で `main` は WIF が通るが `dev` で失敗 | `GCP_WIF_PROVIDER` / `CLASPRC_SECRET` が **protected** 変数になっている。unprotected に変更。 |
| エアギャップ GitLab | WIF は `sts.googleapis.com` + `secretmanager.googleapis.com` への egress が必要。legacy `CLASPRC_JSON` を継続使用。 |
