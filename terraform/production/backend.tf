# リモートステート設定（本番環境用）
#
# GitHub Actions経由でのデプロイ時には、ワークフロー内で
# -backend-config パラメータを使用してS3バケット名などを指定します。
#
# 詳細は docs/aws-manual-setup.md を参照してください。

terraform {
  backend "s3" {
    # GitHub Actionsで -backend-config パラメータにて設定
  }
}
