# AWS環境手動セットアップガイド

このドキュメントでは、CI/CDパイプラインとTerraform Remote Stateを使用するために必要なAWSリソースを手動で作成する手順を説明します。

## セットアップ手順

### 1. S3バケット作成（Terraform State保存用）

#### 目的
Terraformのstateファイルを安全に保存するためのS3バケットを作成します。

#### 手順

1. **AWSコンソールにログイン**
   - https://console.aws.amazon.com/

2. **S3サービスに移動**
   - サービス検索で「S3」を検索

3. **バケットを作成**
   - 「バケットを作成」ボタンをクリック

4. **バケット設定**
   - **バケット名**: `local-gateway-tfstate-<YOUR-ACCOUNT-ID>`
     - 例: `local-gateway-state-123456789012`
     - バケット名はグローバルに一意である必要があります
   - **リージョン**: `ap-northeast-1` (東京)
   - **バケットのバージョニング**: `有効化`
     - Terraformのstate履歴を保持
     - 誤って削除した場合の復旧が可能
   - **デフォルト暗号化**: `有効化`
     - 暗号化タイプ: Amazon S3 マネージドキー (SSE-S3)
   - **パブリックアクセスをすべてブロック**: `有効化`
     - すべてのチェックボックスをON

5. **作成完了**
   - 「バケットを作成」ボタンをクリック
   - S3バケット一覧に作成したバケットが表示されることを確認

---

### 2. DynamoDBテーブル作成（State Lock用）

#### 目的
Terraform実行時の同時実行を防ぐためのロックテーブルを作成します。

#### 手順

1. **DynamoDBサービスに移動**
   - サービス検索で「DynamoDB」を検索

2. **テーブルを作成**
   - 「テーブルを作成」ボタンをクリック

3. **テーブル設定**
   - **テーブル名**: `local-gateway-tfstate-lock`
   - **パーティションキー**: `LockID` (型: 文字列)
     - **重要**: 正確に `LockID` と入力（大文字小文字を区別）
   - **テーブルクラス**: DynamoDB Standard
   - **読み込み/書き込みキャパシティ設定**: オンデマンド
     - 使用量に応じた課金（通常はほぼ無料）

4. **デフォルト設定**
   - その他の設定はデフォルトのまま

5. **作成完了**
   - 「テーブルを作成」ボタンをクリック
   - 作成完了まで数秒待機
   - テーブル一覧でステータスが「アクティブ」になることを確認

---

### 3. OIDC Provider作成

#### 目的
GitHub ActionsがAWSアクセスキーなしでAWSリソースにアクセスできるようにします。

#### 手順

1. **IAMサービスに移動**
   - サービス検索で「IAM」を検索

2. **IDプロバイダー**
   - 左メニューから「IDプロバイダー」を選択
   - 「プロバイダーを追加」ボタンをクリック

3. **プロバイダー設定**
   - **プロバイダーのタイプ**: `OpenID Connect`
   - **プロバイダーのURL**: `https://token.actions.githubusercontent.com`
   - **対象者**: `sts.amazonaws.com`

4. **作成完了**
   - 「プロバイダーを追加」ボタンをクリック
   - IAM → IDプロバイダー で作成したプロバイダーが表示されることを確認
   - ARN形式: `arn:aws:iam::<ACCOUNT-ID>:oidc-provider/token.actions.githubusercontent.com`

---

### 4. IAMロール作成（GitHub Actions用）

#### 目的
GitHub ActionsがAssumeRoleするためのIAMロールを作成します。

#### 手順

1. **IAMロールの作成開始**
   - IAM → ロール → 「ロールを作成」

2. **信頼されたエンティティの選択**
   - **信頼されたエンティティタイプ**: `ウェブアイデンティティ`
   - **アイデンティティプロバイダー**: `token.actions.githubusercontent.com`
   - **Audience**: `sts.amazonaws.com`

3. **信頼ポリシーのカスタマイズ**
   - 「信頼ポリシーをカスタマイズ」を選択
   - 以下のJSONに置き換え（`<GITHUB-USER-OR-ORG>`を自分のGitHubユーザー名または組織名に置き換え）:
   - 以下のJSONに置き換え（`<GITHUB-YOUR-REPO>`を該当のレポジトリ名に置き換え）:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT-ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<GITHUB-USER-OR-ORG>/<GITHUB-YOUR-REPO>:*"
        }
      }
    }
  ]
}
```

4. **許可ポリシーのアタッチ**
   - 「次へ」をクリック

5. **ロール名の設定**
   - **ロール名**: `github-actions-local-gateway`
   - **説明**: `Role for GitHub Actions to deploy infrastructure`

6. **作成完了**
   - 「ロールを作成」ボタンをクリック

#### 補足: S3/DynamoDB管理ポリシーの追加

Terraform Remote Stateのためにインラインポリシーを追加します。

1. **作成したロールを開く**
   - IAM → ロール → `github-actions-local-gateway`

2. **インラインポリシーを追加**
   - 「インラインポリシーを追加」→「JSON」タブ
   - 以下を貼り付け（`<ACCOUNT-ID>`を置き換え）:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-state-<ACCOUNT-ID>",
        "arn:aws:s3:::terraform-state-<ACCOUNT-ID>/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:<ACCOUNT-ID>:table/terraform-state-lock"
    }
  ]
}
```

3. **ポリシー名を設定**
   - **ポリシー名**: `local-gateway-deploy`
   - 「ポリシーの作成」をクリック
   - ロールの詳細画面で「許可」タブにポリシーが追加されたことを確認

4.ポリシーエディタでJSONを選択
  - JSON」タブをクリック
  
5. ポリシーのJSONを貼り付け

```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "TerraformStateAccess",
			"Effect": "Allow",
			"Action": [
				"s3:GetObject",
				"s3:PutObject",
				"s3:DeleteObject",
				"s3:ListBucket"
			],
			"Resource": [
				"arn:aws:s3:::local-gateway-tfstate-<ACCOUNT_ID>",
				"arn:aws:s3:::local-gateway-tfstate-<ACCOUNT_ID>/*"
			]
		},
		{
			"Sid": "TerraformStateLock",
			"Effect": "Allow",
			"Action": [
				"dynamodb:GetItem",
				"dynamodb:PutItem",
				"dynamodb:DeleteItem"
			],
			"Resource": "arn:aws:dynamodb:ap-northeast-1:<ACCOUNT_ID>:table/local-gateway-tfstate-lock"
		},
		{
			"Sid": "LambdaManagement",
			"Effect": "Allow",
			"Action": [
				"lambda:CreateFunction",
				"lambda:UpdateFunctionCode",
				"lambda:UpdateFunctionConfiguration",
				"lambda:DeleteFunction",
				"lambda:GetFunction",
				"lambda:ListFunctions",
				"lambda:AddPermission",
				"lambda:RemovePermission",
				"lambda:InvokeFunction",
				"lambda:TagResource",
				"lambda:UntagResource",
				"lambda:ListTags",
				"lambda:GetFunctionCodeSigningConfig",
				"lambda:ListVersionsByFunction",
				"lambda:GetPolicy"
			],
			"Resource": "arn:aws:lambda:ap-northeast-1:<ACCOUNT_ID>:function:*"
		},
		{
			"Sid": "DynamoDBManagement",
			"Effect": "Allow",
			"Action": [
				"dynamodb:CreateTable",
				"dynamodb:DeleteTable",
				"dynamodb:DescribeTable",
				"dynamodb:UpdateTable",
				"dynamodb:ListTables",
				"dynamodb:TagResource",
				"dynamodb:UntagResource",
				"dynamodb:ListTagsOfResource",
				"dynamodb:DescribeContinuousBackups",
				"dynamodb:DescribeTimeToLive"
			],
			"Resource": "arn:aws:dynamodb:ap-northeast-1:<ACCOUNT_ID>:table/*"
		},
		{
			"Sid": "APIGatewayManagement",
			"Effect": "Allow",
			"Action": [
				"apigateway:GET",
				"apigateway:POST",
				"apigateway:PUT",
				"apigateway:PATCH",
				"apigateway:DELETE",
				"apigateway:UpdateRestApiPolicy"
			],
			"Resource": [
				"arn:aws:apigateway:ap-northeast-1::/restapis",
				"arn:aws:apigateway:ap-northeast-1::/restapis/*",
				"arn:aws:apigateway:ap-northeast-1::/tags/*"
			]
		},
		{
			"Sid": "IAMRoleManagement",
			"Effect": "Allow",
			"Action": [
				"iam:CreateRole",
				"iam:DeleteRole",
				"iam:GetRole",
				"iam:PassRole",
				"iam:AttachRolePolicy",
				"iam:DetachRolePolicy",
				"iam:PutRolePolicy",
				"iam:DeleteRolePolicy",
				"iam:GetRolePolicy",
				"iam:ListRolePolicies",
				"iam:ListAttachedRolePolicies",
				"iam:TagRole",
				"iam:UntagRole",
				"iam:ListRoleTags"
			],
			"Resource": "arn:aws:iam::<ACCOUNT_ID>:role/*"
		},
		{
			"Sid": "CloudWatchLogs",
			"Effect": "Allow",
			"Action": [
				"logs:CreateLogGroup",
				"logs:DeleteLogGroup",
				"logs:DescribeLogGroups",
				"logs:PutRetentionPolicy"
			],
			"Resource": "*"
		},
		{
			"Sid": "IAMPolicyManagement",
			"Effect": "Allow",
			"Action": [
				"iam:CreatePolicy",
				"iam:DeletePolicy",
				"iam:GetPolicy",
				"iam:GetPolicyVersion",
				"iam:ListPolicyVersions",
				"iam:CreatePolicyVersion",
				"iam:DeletePolicyVersion",
				"iam:TagPolicy",
				"iam:UntagPolicy"
			],
			"Resource": "arn:aws:iam::<ACCOUNT_ID>:policy/*"
		}
	]
}
```

---

## GitHub設定

### 1. GitHub Secretsの設定

CI/CDパイプラインで使用するAWSロールARNをGitHub Secretsに登録します。

#### 手順

1. **GitHubリポジトリを開く**
   - ブラウザでリポジトリ（例: `https://github.com/<USER>/local-gateway`）にアクセス

2. **Settings → Secrets and variables → Actions**
   - リポジトリの「Settings」タブをクリック
   - 左メニューから「Secrets and variables」→「Actions」を選択

3. **New repository secretをクリック**
   - 「New repository secret」ボタンをクリック

4. **Secretを追加（1つ目: AWS_ROLE_ARN）**
   - **Name**: `AWS_ROLE_ARN`
   - **Secret**: `arn:aws:iam::<ACCOUNT-ID>:role/github-actions-local-gateway`
     - `<ACCOUNT-ID>`を実際のAWSアカウントIDに置き換え
     - 例: `arn:aws:iam::123456789012:role/github-actions-local-gateway`
   - 「Add secret」ボタンをクリック

5. **Secretを追加（2つ目: TF_STATE_BUCKET）**
   - 再度「New repository secret」ボタンをクリック
   - **Name**: `TF_STATE_BUCKET`
   - **Secret**: `local-gateway-tfstate-<ACCOUNT-ID>`
     - `<ACCOUNT-ID>`を実際のAWSアカウントIDに置き換え
     - 例: `local-gateway-tfstate-123456789012`
   - 「Add secret」ボタンをクリック

6. **確認**
   - Secrets一覧に以下2つが表示されることを確認:
     - `AWS_ROLE_ARN`
     - `TF_STATE_BUCKET`

### 2. GitHub Environmentの作成

本番環境へのデプロイを管理するためのEnvironmentを作成します。

#### 手順

1. **Settings → Environments**
   - リポジトリの「Settings」タブをクリック
   - 左メニューから「Environments」を選択

2. **New environmentをクリック**
   - 「New environment」ボタンをクリック

3. **Environment名を設定**
   - **Name**: `production`
   - 「Configure environment」ボタンをクリック

4. **保護ルールの設定（オプション）**
   - **Required reviewers**: 有効化すると、デプロイ前に承認が必要
   - **Wait timer**: デプロイ前の待機時間を設定
   - 初期設定では特に設定不要

5. **確認**
   - Environments一覧に `production` が表示されることを確認

---

## 作成したリソース一覧

| リソースタイプ | リソース名 | 目的 |
|---------------|-----------|------|
| S3 Bucket | `local-gateway-tfstate-<ACCOUNT-ID>` | Terraform state保存 |
| DynamoDB Table | `local-gateway-tfstate-lock` | Terraform state lock |
| IAM OIDC Provider | `token.actions.githubusercontent.com` | GitHub Actions認証 |
| IAM Role | `github-actions-local-gateway` | GitHub Actions実行ロール |
| IAM Policy (inline) | `local-gateway-deploy` | インフラ管理権限（S3/DynamoDB/Lambda/API Gateway/IAM） |

---



## 次のステップ

AWSリソースとGitHub設定の準備が完了したら、GitHub Actions経由でデプロイを実行します。

### 初回デプロイ実行

1. **Pull Requestを作成**
   ```bash
   git checkout -b setup/initial-deploy
   git push origin setup/initial-deploy
   ```

2. **GitHub ActionsでCI実行**
   - Pull Requestを作成すると、自動的にCI（`.github/workflows/ci.yml`）が実行されます
   - テスト → ビルド → Terraform Plan が実行され、結果がPRにコメントされます

3. **Planの確認**
   - PRのコメントでTerraform Planの結果を確認
   - 以下のリソースが作成される予定であることを確認:
     - Lambda関数（authz-go, test-function）
     - DynamoDB AllowedTokensテーブル
     - API Gateway
     - IAMロール（Lambda用）

4. **mainブランチへマージ**
   - Planに問題がなければ、PRをマージ
   - mainブランチへのpushで自動的にデプロイ（`.github/workflows/deploy.yml`）が実行されます

5. **デプロイ完了確認**
   - GitHub Actionsのログで`terraform apply`の実行結果を確認
   - API Gateway URLが出力されるので、動作確認を実施


---

## 参考資料

- [AWS IAM OIDC Provider Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
