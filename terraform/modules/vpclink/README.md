# VPC Link統合モジュール

このモジュールは、API Gateway + VPC Link + ALB + ECS Fargateを使った本番環境用の構成を提供します。

## アーキテクチャ

```
クライアント
    ↓
API Gateway (REST API)
    ↓
Lambda Authorizer (TOKEN認証 - DynamoDB検証)
    ↓
API Gateway Integration (VPC Link)
    ↓
VPC Link
    ↓
NLB (Network Load Balancer)
    ↓
ALB (Application Load Balancer) - パスベースルーティング
    ├─ /users/*  → Target Group 1 → ECS Fargate (API Server 1 - Users Service)
    └─ /orders/* → Target Group 2 → ECS Fargate (API Server 2 - Orders Service)
```

## なぜNLB → ALB構成なのか？

API Gateway REST APIのVPC Link v1は**NLBのみ**サポートしています。しかし、NLBはレイヤー4（TCP/UDP）で動作するため、HTTPパスベースのルーティングができません。

そのため、以下の構成を採用しています：

1. **VPC Link → NLB**: API Gatewayの要件を満たす
2. **NLB → ALB**: パスベースルーティングを実現
3. **ALB → ECS Fargate**: 各マイクロサービスへのルーティング

### 代替案（HTTP API使用時）

API Gateway HTTP API (v2) を使用する場合は、VPC Link v2がALBを直接サポートするため、NLBは不要です：

```
API Gateway (HTTP API) → VPC Link v2 → ALB → ECS Fargate
```

## リソース構成

### ネットワーク
- VPC (`10.0.0.0/16`)
- プライベートサブネット（マルチAZ: `ap-northeast-1a`, `ap-northeast-1c`）

### ロードバランサー
- **NLB**: VPC Link接続用（内部NLB）
- **ALB**: パスベースルーティング用（内部ALB）
  - `/users/*` → API Server 1
  - `/orders/*` → API Server 2

### ECS
- **ECS Cluster**: Fargateタスクを実行
- **API Server 1 (Users Service)**:
  - タスク定義: `users-api` コンテナ
  - ECSサービス: 希望タスク数 2
  - ターゲットグループ: `users-tg`
- **API Server 2 (Orders Service)**:
  - タスク定義: `orders-api` コンテナ
  - ECSサービス: 希望タスク数 2
  - ターゲットグループ: `orders-tg`

### セキュリティグループ
- **ALB SG**: VPC内部からのHTTPアクセスのみ許可
- **ECS Tasks SG**: ALBからのポート8080アクセスのみ許可

## 使用方法

### 1. モジュールの有効化

`terraform/production/main.tf` でモジュールのコメントアウトを解除：

```hcl
module "vpclink" {
  source = "../modules/vpclink"

  name_prefix        = "gateway-prod"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]
  region             = "ap-northeast-1"

  # API Server 1 (Users Service) 設定
  api_server_1_image         = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/users-api:latest"
  api_server_1_desired_count = 2

  # API Server 2 (Orders Service) 設定
  api_server_2_image         = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/orders-api:latest"
  api_server_2_desired_count = 2

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

### 2. Dockerイメージの準備

ECRにDockerイメージをプッシュ：

```bash
# ECRログイン
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com

# イメージビルド&プッシュ
docker build -t users-api ./path/to/users-api
docker tag users-api:latest 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/users-api:latest
docker push 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/users-api:latest

docker build -t orders-api ./path/to/orders-api
docker tag orders-api:latest 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/orders-api:latest
docker push 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/orders-api:latest
```

### 3. Terraformデプロイ

```bash
cd terraform/production
terraform init
terraform plan
terraform apply
```

### 4. VPC Link統合の確認

```bash
# VPC Linkのステータス確認（AVAILABLEになるまで待つ）
terraform output vpc_link_status

# API Gatewayの設定確認
aws apigateway get-vpc-links --region ap-northeast-1
```

### 5. API Gatewayリソースの追加

VPC Link統合を使用するAPI Gatewayのリソースを追加（コメント例を参照）：

```hcl
resource "aws_api_gateway_resource" "vpclink_proxy" {
  rest_api_id = module.apigateway.api_id
  parent_id   = module.apigateway.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_integration" "vpclink_proxy" {
  rest_api_id             = module.apigateway.api_id
  resource_id             = aws_api_gateway_resource.vpclink_proxy.id
  http_method             = aws_api_gateway_method.vpclink_proxy.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "ANY"
  uri                     = "http://${module.vpclink.alb_dns_name}/{proxy}"
  connection_type         = "VPC_LINK"
  connection_id           = module.vpclink.vpc_link_id

  request_parameters = {
    "integration.request.path.proxy"              = "method.request.path.proxy"
    "integration.request.header.X-Company-Id"     = "context.authorizer.companyId"
    "integration.request.header.X-Scope"          = "context.authorizer.scope"
    "integration.request.header.X-Internal-Token" = "context.authorizer.internalToken"
  }
}
```

## テスト

### エンドツーエンドテスト

```bash
# API Gateway経由でUsers Serviceにアクセス
curl -H "Authorization: Bearer allow" \
  https://your-api-id.execute-api.ap-northeast-1.amazonaws.com/test/users/123

# API Gateway経由でOrders Serviceにアクセス
curl -H "Authorization: Bearer allow" \
  https://your-api-id.execute-api.ap-northeast-1.amazonaws.com/test/orders/456
```

### ALBの直接テスト（VPC内部から）

```bash
# ALB DNS名を取得
terraform output alb_dns_name

# VPC内のEC2インスタンスから直接テスト
curl http://internal-alb-dns-name/users/123
curl http://internal-alb-dns-name/orders/456
```

## コスト見積もり

主なコスト要素：

1. **VPC Link**: $36/月（0.05 USD/時間）
2. **NLB**: $22/月（0.0225 USD/時間 × 730時間） + データ処理料金
3. **ALB**: $22/月（0.0225 USD/時間 × 730時間） + LCU料金
4. **ECS Fargate**: タスク数とサイズによる
   - 0.25 vCPU, 0.5 GB: 約$15/月（タスク2個 × 常時稼働）
5. **CloudWatch Logs**: ログ量による

**合計概算**: $100-150/月（最小構成）

## 注意事項

### VPC Linkのステータス

VPC Linkの作成には**5-10分**かかります。`terraform apply`後、VPC Linkが`AVAILABLE`になるまで待つ必要があります：

```bash
aws apigateway get-vpc-link --vpc-link-id <vpc-link-id>
```

### NLBヘルスチェック

NLB → ALBのヘルスチェックが失敗する場合、ALBのヘルスチェックパス（`/health`）がバックエンドで実装されているか確認してください。

### Fargateタスクの起動

ECSタスクが起動しない場合：

1. ECRイメージが正しくプッシュされているか確認
2. ECS Execution Roleに必要な権限があるか確認
3. CloudWatch Logsでエラーログを確認

```bash
aws logs tail /ecs/gateway-prod-users-service --follow
```

### セキュリティ

- ALBとNLBは**内部ロードバランサー**（インターネットアクセス不可）
- ECSタスクはプライベートサブネットに配置
- API Gateway経由のみアクセス可能

## トラブルシューティング

### VPC Linkが `FAILED` になる

- NLBが正常に動作しているか確認
- サブネット設定が正しいか確認
- NLBのターゲットグループにヘルシーなターゲットがあるか確認

### ALBのターゲットが`unhealthy`

- ECSタスクがポート8080でリッスンしているか確認
- セキュリティグループでALB → ECSの通信が許可されているか確認
- `/health`エンドポイントが200を返すか確認

### API Gatewayから503エラー

- VPC LinkがAVAILABLEか確認
- NLB → ALB → ECSの経路でヘルスチェックがすべてパスしているか確認

## 参考資料

- [AWS VPC Link Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-private-integration.html)
- [ECS Fargate on AWS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
