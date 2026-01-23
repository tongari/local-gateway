# ローカル環境用 Terraform 設定

# DynamoDB テーブル
module "dynamodb" {
  source = "../modules/dynamodb"

  table_name = "AllowedTokens"
  # enable_encryption = false (デフォルト) - LocalStackでは未サポート

  tags = {
    Environment = "local"
    ManagedBy   = "terraform"
  }
}

# Lambda Authorizer 関数
module "lambda_authorizer" {
  source = "../modules/lambda"

  function_name          = "authz-go"
  zip_path               = "/lambda/authz-go/function.zip"
  timeout                = 10  # Authorizer は高速な応答が必要
  iam_role_name          = "lambda-authorizer-role"
  iam_policy_name        = "lambda-authorizer-policy"
  enable_dynamodb_policy = true
  dynamodb_table_name    = module.dynamodb.table_name
  dynamodb_table_arn     = module.dynamodb.table_arn

  tags = {
    Environment = "local"
    ManagedBy   = "terraform"
  }
}

# テスト用 Lambda 関数
module "lambda_test_function" {
  source = "../modules/lambda"

  function_name = "test-function"
  zip_path      = "/lambda/test-function/function.zip"
  timeout       = 10  # テスト用途の軽量関数
  iam_role_name = "lambda-test-function-role"

  tags = {
    Environment = "local"
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

  # レート制限（ローカル開発環境用）
  throttle_burst_limit = 100   # 秒間最大100リクエスト
  throttle_rate_limit  = 50    # 秒間平均50リクエスト

  # VPC Link統合（LocalStackでの検証用）
  # 注意: LocalStackではVPC Linkが完全にサポートされていないため、動作しない可能性があります
  # vpc_link_id          = module.vpclink.vpc_link_id
  # vpc_link_backend_url = "http://${module.vpclink.nlb_dns_name}:8080/"

  tags = {
    Environment = "local"
    ManagedBy   = "terraform"
  }
}

# VPC Link統合（LocalStackでの動作検証用）
# 注意: LocalStackではVPC Linkのサポートが限定的です
# まずは基本環境を動作させてから有効化します
# module "vpclink" {
#   source = "../modules/vpclink-local"
#
#   name_prefix        = "local-gateway"
#   vpc_cidr           = "10.0.0.0/16"
#   availability_zones = ["ap-northeast-1a", "ap-northeast-1c"]
#   backend_port       = 8080
#   # LocalStackでは実際のIPではなく、NLBのDNS名を使用する
#   backend_ips        = []
#
#   tags = {
#     Environment = "local"
#     ManagedBy   = "terraform"
#   }
# }

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

# VPC Link関連の出力（VPC Linkモジュール有効化時に使用）
# output "vpc_link_id" {
#   description = "VPC Link ID"
#   value       = module.vpclink.vpc_link_id
# }
#
# output "vpc_link_status" {
#   description = "VPC Linkのステータス"
#   value       = module.vpclink.vpc_link_status
# }
#
# output "nlb_dns_name" {
#   description = "NLBのDNS名"
#   value       = module.vpclink.nlb_dns_name
# }
