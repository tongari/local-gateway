# GitHub Actions ワークフロー

## 概要

このリポジトリでは以下のGitHub Actionsワークフローを提供しています。

## ワークフロー一覧

### 1. CI (ci.yml)

Pull Requestとmainブランチへのpushで自動的に実行されます。

- **トリガー**: Pull Request、mainブランチへのpush
- **内容**: テストとビルドの実行

### 2. Deploy (deploy.yml)

production環境へのデプロイを行います。

- **トリガー**:
  - mainブランチへのpush（自動デプロイ）
  - workflow_dispatch（手動デプロイ）

## 手動デプロイの使い方

任意のブランチからproduction環境にデプロイする手順：

### 手順

1. **GitHub リポジトリページを開く**
   - リポジトリのメインページに移動します

2. **Actionsタブを開く**
   - 上部メニューから「Actions」をクリック

3. **Deployワークフローを選択**
   - 左サイドバーから「Deploy」ワークフローを選択

4. **Run workflowをクリック**
   - 右上の「Run workflow」ボタンをクリック

5. **パラメータを設定**
   - **Use workflow from**: デプロイしたいブランチを選択（例: `feature/add-new-api`, `main`など）
   - **デプロイ先環境**: `production`（デフォルト）
   - **本当にデプロイしますか？**: `yes` を選択（デプロイを実行する場合）

6. **実行**
   - 緑色の「Run workflow」ボタンをクリックして実行

### 実行フロー

1. **確認チェック** (workflow_dispatchの場合のみ)
   - デプロイ確認が「yes」でない場合は即座に失敗
   - ブランチ、環境、実行者の情報を表示

2. **テスト実行**
   - 全てのGoテストを実行
   - テスト失敗時はデプロイ中止

3. **ビルド**
   - Lambda関数のビルド
   - function.zipの作成

4. **デプロイ**
   - AWS認証（OIDC）
   - Terraformでインフラをデプロイ
   - API Gateway URLを出力

### 安全機能

- **確認ステップ**: デプロイ前に明示的な確認が必要
- **Environment保護**: GitHub Environmentsの保護ルールが適用されます
- **デプロイ情報の表示**: どのブランチから誰がデプロイしたかを記録

## 注意事項

### 権限

- `environment: production`の設定により、GitHub Environmentsの保護ルールが適用されます
- リポジトリの管理者またはEnvironmentで許可されたユーザーのみがデプロイを承認できます

### ブランチ保護

- mainブランチ以外からデプロイする場合は、以下を確認してください：
  - テストが全て成功すること
  - コードレビューが完了していること
  - デプロイの必要性が明確であること

### ロールバック

- 問題が発生した場合は、以前の安定したブランチを選択して再デプロイしてください
- または、AWS管理コンソールから手動でロールバックすることも可能です

## トラブルシューティング

### ワークフローが失敗する場合

1. **確認チェックで失敗**
   - 「本当にデプロイしますか？」で「yes」を選択しているか確認

2. **テストで失敗**
   - ローカルで `make test` を実行して問題を特定
   - テストを修正してから再実行

3. **ビルドで失敗**
   - ローカルで `make build` を実行して問題を特定
   - 依存関係の問題がないか確認

4. **デプロイで失敗**
   - AWS認証情報が正しく設定されているか確認
   - Terraform stateが破損していないか確認
   - AWS管理コンソールでリソースの状態を確認

## 参考リンク

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [workflow_dispatch](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
