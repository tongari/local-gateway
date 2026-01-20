# リモートステート設定（本番環境用）
#
# 使用方法：
# 1. backend-config.hcl を作成（このファイルはGit管理外）
# 2. terraform init -backend-config=backend-config.hcl で初期化
#
# backend-config.hcl の内容例：
# bucket         = "local-gateway-tfstate-123456789012"
# key            = "production/terraform.tfstate"
# region         = "ap-northeast-1"
# dynamodb_table = "local-gateway-tfstate-lock"
# encrypt        = true
#
# 準備手順の詳細は docs/cicd-plan.md を参照してください。

terraform {
  backend "s3" {
    # backend-config.hcl で設定を指定
  }
}
