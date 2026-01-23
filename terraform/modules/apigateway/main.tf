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

# メソッドレスポンス（200 OK）
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.test.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# メソッドレスポンス（500 Internal Server Error）
resource "aws_api_gateway_method_response" "response_500" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.test.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = "500"

  response_models = {
    "application/json" = "Error"
  }
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

# AWS 統合（非Proxy）- Lambda関数統合
#
# 【重要】AWS統合でのヘッダー処理について
# AWS統合では、API GatewayがLambdaをAWS APIで呼び出す際にSignature V4署名を使用します。
# この署名はHTTPヘッダーを含めて計算されるため、署名計算後にヘッダーを変更すると
# 署名検証エラー（InvalidSignatureException）が発生します。
#
# ❌ 使用不可: $context.requestOverride.header
#    - Lambda呼び出しのHTTPヘッダーを上書きしてしまい、署名が壊れる
#    - 例: #set($context.requestOverride.header.X-Company-Id = $context.authorizer.companyId)
#
# ✅ 正しい方法: JSONペイロード内のheadersフィールドに追加
#    - Lambda関数に渡すJSONデータ内に、ヘッダー情報を含める
#    - Lambda呼び出しのHTTPヘッダーは変更しないため、署名は正常
#
# 注意: VPC Link統合（HTTP/HTTPSバックエンド）の場合は、AWS署名を使用しないため
#       $context.requestOverride.headerを使用できます（後述のコメント参照）
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.test.id
  http_method             = aws_api_gateway_method.get.http_method
  type                    = "AWS"
  integration_http_method = "POST"
  uri                     = var.backend_function_invoke_arn

  # マッピングテンプレートを常に適用（パススルーしない）
  passthrough_behavior = "NEVER"

  # リクエストマッピングテンプレート: Authorizerのcontextからヘッダー情報を追加
  # JSONペイロード内のheadersオブジェクトに追加することで、AWS署名を壊さない
  request_templates = {
    "application/json" = <<EOF
{
  "body": "$util.escapeJavaScript($input.body)",
  "headers": {
    #foreach($header in $input.params().header.keySet())
    "$header": "$util.escapeJavaScript($input.params().header.get($header))"#if($foreach.hasNext),#end
    #end
    #if($context.authorizer.companyId && $context.authorizer.companyId != "")
    ,"X-Company-Id": "$context.authorizer.companyId"
    #end
    #if($context.authorizer.scope && $context.authorizer.scope != "")
    ,"X-Scope": "$context.authorizer.scope"
    #end
    #if($context.authorizer.internalToken && $context.authorizer.internalToken != "")
    ,"X-Internal-Token": "Bearer $context.authorizer.internalToken"
    #end
  },
  "httpMethod": "$context.httpMethod",
  "path": "$context.resourcePath"
}
EOF
    # Content-Typeがない場合のデフォルト（GETリクエスト用）
    "$default" = <<EOF
{
  "body": "$util.escapeJavaScript($input.body)",
  "headers": {
    #foreach($header in $input.params().header.keySet())
    "$header": "$util.escapeJavaScript($input.params().header.get($header))"#if($foreach.hasNext),#end
    #end
    #if($context.authorizer.companyId && $context.authorizer.companyId != "")
    ,"X-Company-Id": "$context.authorizer.companyId"
    #end
    #if($context.authorizer.scope && $context.authorizer.scope != "")
    ,"X-Scope": "$context.authorizer.scope"
    #end
    #if($context.authorizer.internalToken && $context.authorizer.internalToken != "")
    ,"X-Internal-Token": "Bearer $context.authorizer.internalToken"
    #end
  },
  "httpMethod": "$context.httpMethod",
  "path": "$context.resourcePath"
}
EOF
  }

  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # VPC Link統合の場合（将来の実装用）
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # VPC Link統合では、NLB/ALB経由でバックエンド（ECS/Fargate等）に通常のHTTP
  # リクエストを送信します。AWS署名を使用しないため、HTTPヘッダーの上書きが可能です。
  #
  # 使用例:
  # type            = "HTTP_PROXY"  # または "HTTP"（非Proxy）
  # connection_type = "VPC_LINK"
  # connection_id   = aws_api_gateway_vpc_link.main.id
  # uri             = "http://internal-alb.example.com/api/endpoint"
  #
  # 方法1: request_parametersを使用（推奨）
  # request_parameters = {
  #   "integration.request.header.X-Company-Id"    = "context.authorizer.companyId"
  #   "integration.request.header.X-Scope"         = "context.authorizer.scope"
  #   "integration.request.header.X-Internal-Token" = "context.authorizer.internalToken"
  # }
  #
  # 方法2: マッピングテンプレートでヘッダー上書き（HTTP統合の場合）
  # request_templates = {
  #   "application/json" = <<EOF
  # #set($context.requestOverride.header.X-Company-Id = $context.authorizer.companyId)
  # #set($context.requestOverride.header.X-Scope = $context.authorizer.scope)
  # #set($context.requestOverride.header.Authorization = "Bearer $context.authorizer.internalToken")
  # $input.json('$')
  # EOF
  # }
  #
  # 注意: VPC Linkの場合、バックエンドは通常のHTTPヘッダーとして値を受け取ります
  #
  # 【統合レスポンス】
  # - HTTP_PROXY: 統合レスポンス不要（バックエンドのレスポンスをそのまま返す）
  # - HTTP (非Proxy): 統合レスポンスが必要（レスポンス変換が必要な場合）
  #
  # HTTP_PROXYの場合（推奨）:
  # 統合レスポンスリソースは不要。バックエンドが直接HTTPレスポンスを返す。
  #
  # HTTP（非Proxy）の場合:
  # resource "aws_api_gateway_integration_response" "vpclink_response_200" {
  #   rest_api_id = aws_api_gateway_rest_api.api.id
  #   resource_id = aws_api_gateway_resource.test.id
  #   http_method = aws_api_gateway_method.get.http_method
  #   status_code = "200"
  #
  #   selection_pattern = ""  # デフォルトレスポンス
  #
  #   response_templates = {
  #     "application/json" = "$input.json('$')"  # バックエンドのレスポンスをそのまま返す
  #   }
  # }
  # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
}

# 統合レスポンス（Lambda→API Gateway）- 成功時
resource "aws_api_gateway_integration_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.test.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  # Lambda関数が正常に実行された場合（エラーをthrowしない場合）
  # selection_patternが空 = デフォルトレスポンス
  selection_pattern = ""

  # レスポンスマッピングテンプレート: Lambdaのレスポンスをそのまま返す
  response_templates = {
    "application/json" = <<EOF
$input.json('$')
EOF
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

# 統合レスポンス（Lambda→API Gateway）- エラー時
# 注意: AWS統合では、Lambda実行エラー時のみこのレスポンスが使用される
# Lambda関数がエラーをthrowするとAPI Gatewayにエラーメッセージが返される
resource "aws_api_gateway_integration_response" "response_500" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.test.id
  http_method = aws_api_gateway_method.get.http_method
  status_code = aws_api_gateway_method_response.response_500.status_code

  # Lambda実行エラー時のパターン（errorMessageフィールドの存在を確認）
  # 通常のレスポンスにマッチしないよう厳密なパターンを使用
  selection_pattern = "^\\{.*\"errorMessage\".*\\}$"

  # エラーレスポンスのマッピングテンプレート
  response_templates = {
    "application/json" = <<EOF
{
  "message": "Internal server error",
  "error": "$util.escapeJavaScript($input.path('$.errorMessage'))"
}
EOF
  }

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

# デプロイ
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # メソッドと統合が作成されてからデプロイ
  depends_on = [
    aws_api_gateway_method.get,
    aws_api_gateway_method_response.response_200,
    aws_api_gateway_method_response.response_500,
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration_response.response_200,
    aws_api_gateway_integration_response.response_500
  ]

  # 設定変更時に再デプロイするためのトリガー
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.test.id,
      aws_api_gateway_method.get.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_integration.lambda_integration.request_templates,
      aws_api_gateway_method_response.response_200.id,
      aws_api_gateway_method_response.response_500.id,
      aws_api_gateway_integration_response.response_200.id,
      aws_api_gateway_integration_response.response_200.response_templates,
      aws_api_gateway_integration_response.response_200.selection_pattern,
      aws_api_gateway_integration_response.response_500.id,
      aws_api_gateway_integration_response.response_500.response_templates,
      aws_api_gateway_integration_response.response_500.selection_pattern,
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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VPC Link統合用リソース（オプション）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# /vpclink リソース（VPC Link統合が有効な場合のみ作成）
resource "aws_api_gateway_resource" "vpclink" {
  count       = var.vpc_link_id != null ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "vpclink"
}

# VPC Link用 GET メソッド
resource "aws_api_gateway_method" "vpclink_get" {
  count         = var.vpc_link_id != null ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.vpclink[0].id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.token_authorizer.id
}

# VPC Link用メソッドレスポンス（200 OK）
resource "aws_api_gateway_method_response" "vpclink_response_200" {
  count       = var.vpc_link_id != null ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.vpclink[0].id
  http_method = aws_api_gateway_method.vpclink_get[0].http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# VPC Link統合（HTTP_PROXY）
# VPC Link経由でNLB → バックエンドサーバーにリクエストを転送
resource "aws_api_gateway_integration" "vpclink_integration" {
  count                   = var.vpc_link_id != null ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.vpclink[0].id
  http_method             = aws_api_gateway_method.vpclink_get[0].http_method
  type                    = "HTTP_PROXY"
  connection_type         = "VPC_LINK"
  connection_id           = var.vpc_link_id
  integration_http_method = "GET"
  uri                     = var.vpc_link_backend_url

  # Authorizerから取得した情報をヘッダーとして追加
  request_parameters = {
    "integration.request.header.X-Company-Id"    = "context.authorizer.companyId"
    "integration.request.header.X-Scope"         = "context.authorizer.scope"
    "integration.request.header.X-Internal-Token" = "context.authorizer.internalToken"
  }
}
