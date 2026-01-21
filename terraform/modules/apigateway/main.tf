# API Gateway モジュール
# REST API、リソース、メソッド、Authorizer、統合、デプロイを作成

# REST API
resource "aws_api_gateway_rest_api" "api" {
  name = var.api_name

  tags = var.tags
}

# /test リソース
resource "aws_api_gateway_resource" "test" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "test"
}

# Lambda Authorizer
resource "aws_api_gateway_authorizer" "token_authorizer" {
  name                             = "token-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.api.id
  type                             = "TOKEN"
  authorizer_uri                   = var.authorizer_function_invoke_arn
  identity_source                  = "method.request.header.Authorization"
  # TODO(本番): TTLを300-3600秒に変更してパフォーマンスとコストを改善
  # 現在1秒はテスト/開発用。本番では認可結果をキャッシュすることでDynamoDB呼び出しを削減
  authorizer_result_ttl_in_seconds = 1
}

# Lambda Authorizer への呼び出し権限
resource "aws_lambda_permission" "authorizer_permission" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# バックエンド Lambda への呼び出し権限
resource "aws_lambda_permission" "backend_permission" {
  statement_id  = "AllowAPIGatewayInvokeBackend"
  action        = "lambda:InvokeFunction"
  function_name = var.backend_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# GET メソッド
resource "aws_api_gateway_method" "get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.test.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.token_authorizer.id
}

# メソッドレベルのスロットリング設定
resource "aws_api_gateway_method_settings" "throttling" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
  method_path = "${aws_api_gateway_resource.test.path_part}/${aws_api_gateway_method.get.http_method}"

  settings {
    throttling_burst_limit = var.throttle_burst_limit
    throttling_rate_limit  = var.throttle_rate_limit
    logging_level          = "OFF" # CloudWatch Logsアカウント設定が必要なため無効化
    data_trace_enabled     = false
    metrics_enabled        = true
  }
}

# AWS_PROXY 統合（バックエンド Lambda 関数を呼び出す）
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.test.id
  http_method             = aws_api_gateway_method.get.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = var.backend_function_invoke_arn
}

# デプロイ
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # メソッドと統合が作成されてからデプロイ
  depends_on = [
    aws_api_gateway_method.get,
    aws_api_gateway_integration.lambda_integration
  ]

  # 設定変更時に再デプロイするためのトリガー
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.test.id,
      aws_api_gateway_method.get.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_authorizer.token_authorizer.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ステージ
resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name

  # TODO(本番): CloudWatch Logsを有効化してデバッグとモニタリングを改善
  # access_log_settings {
  #   destination_arn = aws_cloudwatch_log_group.api_gateway.arn
  #   format         = jsonencode({
  #     requestId      = "$context.requestId"
  #     ip             = "$context.identity.sourceIp"
  #     caller         = "$context.identity.caller"
  #     user           = "$context.identity.user"
  #     requestTime    = "$context.requestTime"
  #     httpMethod     = "$context.httpMethod"
  #     resourcePath   = "$context.resourcePath"
  #     status         = "$context.status"
  #     protocol       = "$context.protocol"
  #     responseLength = "$context.responseLength"
  #   })
  # }

  tags = var.tags
}
