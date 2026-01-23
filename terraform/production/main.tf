# 本番環境用 Terraform 設定

# DynamoDB テーブル
module "dynamodb" {
  source = "../modules/dynamodb"

  table_name         = "AllowedTokens"
  enable_encryption  = true  # 本番環境では暗号化を有効化

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Lambda Authorizer 関数
module "lambda_authorizer" {
  source = "../modules/lambda"

  function_name          = "authz-go"
  zip_path               = "${path.module}/../../lambda/authz-go/function.zip"
  timeout                = 10  # Authorizer は高速な応答が必要
  iam_role_name          = "lambda-authorizer-role"
  iam_policy_name        = "lambda-authorizer-policy"
  enable_dynamodb_policy = true
  dynamodb_table_name    = module.dynamodb.table_name
  dynamodb_table_arn     = module.dynamodb.table_arn

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# テスト用 Lambda 関数
module "lambda_test_function" {
  source = "../modules/lambda"

  function_name = "test-function"
  zip_path      = "${path.module}/../../lambda/test-function/function.zip"
  timeout       = 10  # テスト用途の軽量関数
  iam_role_name = "lambda-test-function-role"

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# API Gateway
module "apigateway" {
  source = "../modules/apigateway"

  api_name                       = "local-gateway-api"
  stage_name                     = "test"
  region                         = "ap-northeast-1"
  authorizer_function_name       = module.lambda_authorizer.function_name
  authorizer_function_invoke_arn = module.lambda_authorizer.invoke_arn
  backend_function_name          = module.lambda_test_function.function_name
  backend_function_invoke_arn    = module.lambda_test_function.invoke_arn

  # レート制限（本番環境用: 適切な値に調整）
  throttle_burst_limit = 100   # 秒間最大100リクエスト
  throttle_rate_limit  = 50    # 秒間平均50リクエスト

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  【未検証！！！！】
# VPC Link統合（本番実装用 - コメントアウト）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# 使用方法:
# 1. このブロックのコメントアウトを解除
# 2. api_server_1_image と api_server_2_image を実際のDockerイメージに変更
# 3. terraform apply を実行
#
# アーキテクチャ:
# API Gateway → Lambda Authorizer (認可)
#     ↓
# API Gateway → VPC Link → NLB → ALB → ECS Fargate
#                                  ├─ /users/*  → API Server 1 (Users Service)
#                                  └─ /orders/* → API Server 2 (Orders Service)
#
# module "vpclink" {
#   source = "../modules/vpclink"
#
#   name_prefix        = "gateway-prod"
#   vpc_cidr           = "10.0.0.0/16"
#   availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]
#   region             = "ap-northeast-1"
#
#   # API Server 1 (Users Service) 設定
#   api_server_1_image         = "your-ecr-repo/users-api:latest"
#   api_server_1_desired_count = 2
#
#   # API Server 2 (Orders Service) 設定
#   api_server_2_image         = "your-ecr-repo/orders-api:latest"
#   api_server_2_desired_count = 2
#
#   tags = {
#     Environment = "production"
#     ManagedBy   = "terraform"
#     Project     = "local-gateway-pro"
#   }
# }
#
# # VPC Link統合を使用するAPI Gatewayリソース
# # 既存のapigatewaymモジュールを拡張するか、新しいリソースを追加
# #
# # 例: {proxy+} を使ったVPC Link統合
# # resource "aws_api_gateway_resource" "vpclink_proxy" {
# #   rest_api_id = module.apigateway.api_id
# #   parent_id   = module.apigateway.root_resource_id
# #   path_part   = "{proxy+}"
# # }
# #
# # resource "aws_api_gateway_method" "vpclink_proxy" {
# #   rest_api_id   = module.apigateway.api_id
# #   resource_id   = aws_api_gateway_resource.vpclink_proxy.id
# #   http_method   = "ANY"
# #   authorization = "CUSTOM"
# #   authorizer_id = module.apigateway.authorizer_id
# # }
# #
# # resource "aws_api_gateway_integration" "vpclink_proxy" {
# #   rest_api_id             = module.apigateway.api_id
# #   resource_id             = aws_api_gateway_resource.vpclink_proxy.id
# #   http_method             = aws_api_gateway_method.vpclink_proxy.http_method
# #   type                    = "HTTP_PROXY"
# #   integration_http_method = "ANY"
# #   uri                     = "http://${module.vpclink.alb_dns_name}/{proxy}"
# #   connection_type         = "VPC_LINK"
# #   connection_id           = module.vpclink.vpc_link_id
# #
# #   request_parameters = {
# #     "integration.request.path.proxy" = "method.request.path.proxy"
# #     # Authorizerのcontextをヘッダーに追加
# #     "integration.request.header.X-Company-Id"    = "context.authorizer.companyId"
# #     "integration.request.header.X-Scope"         = "context.authorizer.scope"
# #     "integration.request.header.X-Internal-Token" = "context.authorizer.internalToken"
# #   }
# # }
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 出力
output "dynamodb_table_name" {
  description = "作成された DynamoDB テーブル名"
  value       = module.dynamodb.table_name
}

output "dynamodb_table_arn" {
  description = "作成された DynamoDB テーブルの ARN"
  value       = module.dynamodb.table_arn
}

output "lambda_function_name" {
  description = "Lambda Authorizer 関数名"
  value       = module.lambda_authorizer.function_name
}

output "lambda_function_arn" {
  description = "Lambda Authorizer 関数の ARN"
  value       = module.lambda_authorizer.function_arn
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = module.apigateway.api_id
}

output "api_gateway_invoke_url" {
  description = "API Gateway 呼び出し URL"
  value       = module.apigateway.invoke_url
}

# VPC Link統合の出力（コメントアウト）
# output "vpc_link_id" {
#   description = "VPC LinkのID"
#   value       = module.vpclink.vpc_link_id
# }
#
# output "vpc_link_status" {
#   description = "VPC Linkのステータス (AVAILABLE になるまで待つ)"
#   value       = module.vpclink.vpc_link_status
# }
#
# output "alb_dns_name" {
#   description = "ALBのDNS名"
#   value       = module.vpclink.alb_dns_name
# }
#
# output "nlb_dns_name" {
#   description = "NLBのDNS名"
#   value       = module.vpclink.nlb_dns_name
# }
#
# output "ecs_cluster_name" {
#   description = "ECSクラスター名"
#   value       = module.vpclink.ecs_cluster_name
# }
#
# output "api_server_1_service_name" {
#   description = "API Server 1 (Users Service) のECSサービス名"
#   value       = module.vpclink.api_server_1_service_name
# }
#
# output "api_server_2_service_name" {
#   description = "API Server 2 (Orders Service) のECSサービス名"
#   value       = module.vpclink.api_server_2_service_name
# }
