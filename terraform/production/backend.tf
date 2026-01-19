# リモートステート設定（本番環境用）
#
# 使用する前に以下を準備してください：
# 1. S3 バケットを作成: local-gateway-tfstate-<ACCOUNT_ID>
# 2. DynamoDB テーブルを作成（ロック用）: local-gateway-tfstate-lock
# 3. <ACCOUNT_ID> を実際のAWSアカウントIDに置き換えてください
#
# 準備手順の詳細は docs/cicd-plan.md を参照してください。

terraform {
  backend "s3" {
    bucket         = "local-gateway-tfstate-<ACCOUNT_ID>"
    key            = "production/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "local-gateway-tfstate-lock"
    encrypt        = true
  }
}
