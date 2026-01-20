# DynamoDB テーブル定義
# AllowedTokens テーブル - Lambda Authorizer で使用される許可トークンを格納

resource "aws_dynamodb_table" "allowed_tokens" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token"

  attribute {
    name = "token"
    type = "S"
  }

  # 保存時の暗号化（Encryption at Rest）
  # LocalStackでは未サポートのため、enable_encryption=trueで本番環境のみ有効化
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled = true
    }
  }

  tags = var.tags
}
