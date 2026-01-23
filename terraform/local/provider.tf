# LocalStack 用 AWS プロバイダー設定

provider "aws" {
  region                      = "ap-northeast-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    dynamodb       = "http://localstack:4566"
    lambda         = "http://localstack:4566"
    apigateway     = "http://localstack:4566"
    iam            = "http://localstack:4566"
    s3             = "http://localstack:4566"
    ec2            = "http://localstack:4566"
    elbv2          = "http://localstack:4566"
    logs           = "http://localstack:4566"
    ecs            = "http://localstack:4566"
    elasticloadbalancing = "http://localstack:4566"
  }
}
