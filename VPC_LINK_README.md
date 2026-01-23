# VPC Link統合 - LocalStack検証用ドキュメント

## 概要

このドキュメントは、LocalStack環境でVPC Link統合を試すための手順と制限事項をまとめたものです。

## 実装内容

### 1. バックエンドサーバー
- `backend-server/` - Goで実装したシンプルなHTTPサーバー
- ポート: 8080
- エンドポイント:
  - `/health` - ヘルスチェック
  - `/` - メインハンドラー（リクエスト情報をJSON形式で返却）

### 2. VPC Link統合モジュール
- `terraform/modules/vpclink-local/` - LocalStack用簡易版VPC Linkモジュール
- 構成:
  - VPC + プライベートサブネット
  - Network Load Balancer (NLB)
  - VPC Link (REST API用)
  - ターゲットグループ

### 3. API Gatewayモジュール拡張
- `terraform/modules/apigateway/main.tf` - VPC Link統合リソース追加
- `/vpclink` エンドポイント（VPC Link経由でバックエンドサーバーに接続）
- HTTP_PROXYタイプの統合
- Authorizerからのヘッダー転送機能

## LocalStackの制限事項

### ⚠️ 現在確認されている制限

1. **VPC Linkのサポート状況**
   - LocalStackのCommunity版では、VPC Link機能のサポートが限定的
   - Pro版でも完全な動作保証はされていない可能性が高い

2. **ECS/Fargateサポート**
   - LocalStackでのECS/Fargateサポートは不完全
   - コンテナ起動やタスク管理が正常に動作しない場合がある

3. **ネットワーク構成**
   - Docker Composeネットワーク内でのVPC Linkルーティングは未検証
   - NLBからバックエンドへの接続が確立できない可能性が高い

## デプロイ手順

### 基本環境のデプロイ（VPC Linkなし）

```bash
# Lambda関数のビルド
make build

# 環境起動
docker compose up -d

# テスト実行
make exec-curl TOKEN=allow
```

### VPC Link統合の有効化（試験的）

1. `terraform/local/main.tf` でVPC Linkモジュールのコメントを解除:

```terraform
module "vpclink" {
  source = "../modules/vpclink-local"

  name_prefix        = "local-gateway"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]
  backend_port       = 8080
  backend_ips        = []

  tags = {
    Environment = "local"
    ManagedBy   = "terraform"
  }
}
```

2. API Gatewayモジュールのパラメータを有効化:

```terraform
module "apigateway" {
  # ... 既存の設定 ...

  # VPC Link統合
  vpc_link_id          = module.vpclink.vpc_link_id
  vpc_link_backend_url = "http://${module.vpclink.nlb_dns_name}:8080/"
}
```

3. VPC Link関連の出力を有効化:

```terraform
output "vpc_link_id" {
  description = "VPC Link ID"
  value       = module.vpclink.vpc_link_id
}

output "vpc_link_status" {
  description = "VPC Linkのステータス"
  value       = module.vpclink.vpc_link_status
}

output "nlb_dns_name" {
  description = "NLBのDNS名"
  value       = module.vpclink.nlb_dns_name
}
```

4. 再デプロイ:

```bash
docker compose down
docker compose up -d
```

### VPC Link経由のテスト

```bash
# API ID取得
API_ID=$(docker exec gateway-awscli aws apigateway get-rest-apis \
  --endpoint-url http://localstack:4566 \
  --region ap-northeast-1 \
  --query 'items[0].id' \
  --output text)

# VPC Link経由でアクセス
curl -H "Authorization: Bearer allow" \
  "http://${API_ID}.execute-api.localhost.localstack.cloud:4666/test/vpclink"
```

## AWS本番環境へのデプロイ

LocalStackでの検証後、AWS本番環境にデプロイする場合:

1. `terraform/production/` ディレクトリを使用
2. フル機能の `terraform/modules/vpclink/` モジュールを使用
3. ECS Fargateを使用したマイクロサービス構成が利用可能
4. ALB + NLB構成でのパスベースルーティング

詳細は `terraform/modules/vpclink/main.tf` のコメントを参照してください。

## トラブルシューティング

### Terraformエラー: "count depends on resource attributes"

**原因**: `vpc_link_id`が他のリソースから動的に取得されるため、countの値が決定できない

**解決策**:
1. VPC Linkモジュールを先にデプロイ
2. または、API Gatewayモジュールの条件付きリソース作成を削除

### VPC Link接続エラー

**原因**: LocalStackのVPC Link機能制限

**解決策**:
1. LocalStack Proへのアップグレードを検討
2. AWS本番環境での検証
3. 代替として、Lambda統合のまま使用

## 参考資料

- [LocalStack VPC Link Support](https://docs.localstack.cloud/user-guide/aws/apigateway/)
- [AWS VPC Link Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-private-integration.html)
- [Terraform AWS Provider - VPC Link](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_vpc_link)

## まとめ

- ✅ バックエンドサーバー実装完了
- ✅ VPC Link統合Terraformモジュール作成完了
- ✅ API GatewayへのVPC Link統合機能追加完了
- ⚠️ LocalStackでの動作検証は制限事項により未完了
- 📝 AWS本番環境での検証を推奨

LocalStackでのVPC Link機能は限定的なサポートのため、完全な動作確認にはAWS本番環境またはLocalStack Proが必要です。
