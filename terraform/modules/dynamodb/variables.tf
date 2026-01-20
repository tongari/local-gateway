# DynamoDB モジュールの変数定義

variable "table_name" {
  description = "DynamoDB テーブル名"
  type        = string
  default     = "AllowedTokens"
}

variable "enable_encryption" {
  description = "保存時の暗号化を有効化するか（LocalStackでは無効化推奨）"
  type        = bool
  default     = false
}

variable "tags" {
  description = "リソースに付与するタグ"
  type        = map(string)
  default     = {}
}
