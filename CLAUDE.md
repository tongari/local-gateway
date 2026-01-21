# CLAUDE.md

このファイルは、Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイダンスを提供します。

## プロジェクト概要

LocalStackを使用したLambda AuthorizerのPoC。DynamoDBでのトークン検証によるJWTベース認可を実装。

**アーキテクチャ**: クライアント → API Gateway (REST) → Lambda Authorizer (TOKEN) → DynamoDB → Allow/Deny

## 主要コマンド

```bash
# Lambda関数のビルド（docker compose upの前に必須）
make build

# 環境起動（LocalStack、DynamoDB admin等）
docker compose up -d

# ビルドとデプロイ
make deploy

# テスト実行（LocalStack起動が必要）
make test
make test TEST_TARGET=./authz-go/...  # 特定パッケージ
make test TEST_ARGS="-v"              # 詳細出力

# API Gatewayテスト
make exec-curl TOKEN=allow
make exec-curl TOKEN=invalid-token

# Lambda直接実行
make exec-lambda LAMBDA_NAME=authz-go PAYLOAD='{"type":"TOKEN","authorizationToken":"Bearer allow","methodArn":"arn:aws:execute-api:ap-northeast-1:000000000000:test/test/GET"}'

# リソース確認
make list-lambdas
make get-api-id
make check-apigateway

# クリーンアップ
make clean              # ビルド成果物削除
make clean-localstack   # LocalStackリソース削除
```

## アーキテクチャ

### Lambda関数 (Go)
- `lambda/authz-go/` - Lambda Authorizer: DynamoDB `AllowedTokens`テーブルでトークン検証
- `lambda/test-function/` - テスト用バックエンド関数
- `lambda/testutil/` - 共有テストユーティリティ（DynamoDBヘルパー、LocalStack設定）
- 全関数は`lambda/go.mod`を共有（Go workspace `go.work`使用）

### Terraform構成
- `terraform/modules/` - 再利用可能モジュール: dynamodb, lambda, apigateway
- `terraform/local/` - LocalStack用設定
- `terraform/production/` - AWS本番用設定

### Docker Composeサービス
- `localstack` - AWSサービスエミュレータ (gateway-localstack)
- `dynamodb-admin` - GUI http://localhost:8001
- `go-dev` - Goビルド環境 (gateway-go-dev)
- `terraform` - インフラデプロイ (gateway-terraform)
- `awscli` - AWS CLIとシードデータ (gateway-awscli)

## テストについて

- LocalStack統合テスト（モックではない）
- テスト用テーブル: `AllowedTokens_Test`（自動作成・削除）
- 各テストはユニークなトークンを使用（テスト間の干渉防止）
- テスト実行にはLocalStack起動が必要

## 重要事項

- `docker compose up`の前に必ず`make build`を実行（`function.zip`生成）
- LocalStack用AWS CLIコマンドには`--endpoint-url=http://localstack:4566`が必要
- DynamoDBトークンスキーマ: `token` (String PK), `active` (Boolean, 省略可 - falseで拒否)
