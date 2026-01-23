# LocalStack用 VPC Link統合モジュール - 変数定義

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
  description = "使用するアベイラビリティゾーン"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "backend_port" {
  description = "バックエンドサーバーのポート番号"
  type        = number
  default     = 8080
}

variable "backend_ips" {
  description = "バックエンドサーバーのIPアドレスリスト"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "すべてのリソースに適用するタグ"
  type        = map(string)
  default     = {}
}
