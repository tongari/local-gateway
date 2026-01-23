# VPC Link統合モジュール - 変数定義

variable "name_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "gateway"
}

variable "vpc_cidr" {
  description = "VPC CIDR ブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "使用するアベイラビリティゾーン（マルチAZ構成）"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

# API Server 1 (Users Service) 設定
variable "api_server_1_image" {
  description = "API Server 1 (Users Service) のDockerイメージ"
  type        = string
  default     = "nginx:alpine" # 検証用: 実際のイメージに変更
}

variable "api_server_1_desired_count" {
  description = "API Server 1の希望タスク数"
  type        = number
  default     = 2
}

# API Server 2 (Orders Service) 設定
variable "api_server_2_image" {
  description = "API Server 2 (Orders Service) のDockerイメージ"
  type        = string
  default     = "nginx:alpine" # 検証用: 実際のイメージに変更
}

variable "api_server_2_desired_count" {
  description = "API Server 2の希望タスク数"
  type        = number
  default     = 2
}

variable "tags" {
  description = "すべてのリソースに適用するタグ"
  type        = map(string)
  default     = {}
}
