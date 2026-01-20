# Lambda モジュール
# IAM Role、Policy（オプション）、Lambda 関数を作成

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = var.iam_role_name != null ? var.iam_role_name : "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# IAM Policy for DynamoDB access（enable_dynamodb_policy が true の場合のみ作成）
resource "aws_iam_policy" "lambda_policy" {
  count = var.enable_dynamodb_policy ? 1 : 0

  name = var.iam_policy_name != null ? var.iam_policy_name : "${var.function_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem"
      ]
      Resource = var.dynamodb_table_arn
    }]
  })

  tags = var.tags
}

# Attach policy to role（enable_dynamodb_policy が true の場合のみ）
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  count = var.enable_dynamodb_policy ? 1 : 0

  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy[0].arn
}

# Lambda function
resource "aws_lambda_function" "function" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout

  filename         = var.zip_path
  source_code_hash = filebase64sha256(var.zip_path)

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 || var.dynamodb_table_name != "" ? [1] : []
    content {
      variables = merge(
        var.dynamodb_table_name != "" ? { DYNAMODB_TABLE_NAME = var.dynamodb_table_name } : {},
        var.environment_variables
      )
    }
  }

  tags = var.tags
}
