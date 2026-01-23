# API Gateway モジュール変数定義

variable "api_name" {
  description = "REST API 名"
  type        = string
}

variable "stage_name" {
  description = "デプロイステージ名"
  type        = string
  default     = "test"
}

variable "authorizer_function_name" {
  description = "Lambda Authorizer 関数名"
  type        = string
}

variable "authorizer_function_invoke_arn" {
  description = "Lambda Authorizer 関数の Invoke ARN"
  type        = string
}

variable "backend_function_name" {
  description = "バックエンド Lambda 関数名"
  type        = string
}

variable "backend_function_invoke_arn" {
  description = "バックエンド Lambda 関数の Invoke ARN"
  type        = string
}

variable "region" {
  description = "AWS リージョン"
  type        = string
}

variable "throttle_burst_limit" {
  description = "API Gatewayのバーストリミット（秒間最大リクエスト数）"
  type        = number
  default     = 5000
}

variable "throttle_rate_limit" {
  description = "API Gatewayのレートリミット（秒間平均リクエスト数）"
  type        = number
  default     = 10000
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}

# VPC Link 統合用の変数（オプション）
variable "vpc_link_id" {
  description = "VPC Link ID（VPC Link統合を使用する場合）"
  type        = string
  default     = null
}

variable "vpc_link_backend_url" {
  description = "VPC Link経由でアクセスするバックエンドURL"
  type        = string
  default     = null
}
