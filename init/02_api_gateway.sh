#!/bin/sh
# API Gateway (REST API) の作成と設定
#
# このスクリプトは以下の処理を実行します：
# 1. Lambda Authorizer関数（authz-go）のARNを取得
# 2. REST API（local-gateway-api）の作成または取得
# 3. リソース（/test）の作成または取得
# 4. TOKENタイプのAuthorizer（token-authorizer）の作成または取得
# 5. Lambda関数へのAPI Gatewayからの呼び出し権限を付与
# 6. HTTPメソッド（GET）の設定とAuthorizerの関連付け
# 7. AWS_PROXY統合の設定（test-function Lambda関数を呼び出す）
# 8. APIのデプロイ（testステージ）
# 9. デプロイ後のAPI URLを表示
#
# 注意: 既存のリソースが存在する場合は取得し、存在しない場合は作成します。
set -eu

ENDPOINT="http://localstack:4566"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="authz-go"
API_NAME="local-gateway-api"
STAGE_NAME="test"
RESOURCE_PATH="/test"
HTTP_METHOD="GET"

echo "[apigateway] waiting for Lambda function to be ready..."
sleep 2

# Lambda関数のARNを取得
FUNCTION_ARN=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'Configuration.FunctionArn' \
  --output text 2>/dev/null)

if [ -z "$FUNCTION_ARN" ]; then
  echo "[apigateway] ERROR: Lambda function '$FUNCTION_NAME' not found"
  exit 1
fi

echo "[apigateway] Lambda function ARN: $FUNCTION_ARN"

# REST APIの作成または取得
echo "[apigateway] creating/getting REST API: $API_NAME"
API_ID=$(aws apigateway create-rest-api \
  --name "$API_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws apigateway get-rest-apis \
    --endpoint-url="$ENDPOINT" \
    --query "items[?name=='${API_NAME}'].id" \
    --output text | head -n1)

if [ -z "$API_ID" ]; then
  echo "[apigateway] ERROR: Failed to create or get REST API"
  exit 1
fi

echo "[apigateway] API ID: $API_ID"

# ルートリソースIDを取得
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id "$API_ID" \
  --endpoint-url="$ENDPOINT" \
  --query "items[?path=='/'].id" \
  --output text)

echo "[apigateway] root resource ID: $ROOT_RESOURCE_ID"

# リソースの作成または取得
echo "[apigateway] creating/getting resource: $RESOURCE_PATH"
RESOURCE_ID=$(aws apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_RESOURCE_ID" \
  --path-part "$(echo $RESOURCE_PATH | sed 's|^/||')" \
  --endpoint-url="$ENDPOINT" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --endpoint-url="$ENDPOINT" \
    --query "items[?path=='${RESOURCE_PATH}'].id" \
    --output text | head -n1)

if [ -z "$RESOURCE_ID" ]; then
  echo "[apigateway] ERROR: Failed to create or get resource"
  exit 1
fi

echo "[apigateway] resource ID: $RESOURCE_ID"

# Authorizerの作成または取得
echo "[apigateway] creating/getting authorizer"
# LocalStack用のauthorizer URI形式
# 「2015-03-31 は意味があります。AWS API GatewayのLambda統合URIの標準形式で、APIバージョン（リリース日）を表します。」とのこと。
# @see https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/integration-request-basic-setup.html
# authorizer-result-ttl-in-secondsは、Authorizerの結果をキャッシュする時間を秒単位で指定します。
# ここでは1秒に設定しています。検証用に短い時間に設定しています。
AUTHORIZER_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations"
AUTHORIZER_ID=$(aws apigateway create-authorizer \
  --rest-api-id "$API_ID" \
  --name "token-authorizer" \
  --type TOKEN \
  --authorizer-uri "$AUTHORIZER_URI" \
  --identity-source "method.request.header.Authorization" \
  --authorizer-result-ttl-in-seconds 1 \
  --endpoint-url="$ENDPOINT" \
  --query 'id' \
  --output text 2>/dev/null || \
  aws apigateway get-authorizers \
    --rest-api-id "$API_ID" \
    --endpoint-url="$ENDPOINT" \
    --query "items[?name=='token-authorizer'].id" \
    --output text | head -n1)

if [ -z "$AUTHORIZER_ID" ]; then
  echo "[apigateway] ERROR: Failed to create or get authorizer"
  exit 1
fi

echo "[apigateway] authorizer ID: $AUTHORIZER_ID"

# Lambda関数（authz-go）にAPI Gatewayからの呼び出し権限を付与
echo "[apigateway] granting invoke permission to Lambda (authz-go)"
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "apigateway-invoke-$(date +%s)" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:000000000000:${API_ID}/*/*" \
  --endpoint-url="$ENDPOINT" 2>/dev/null || echo "[apigateway] permission may already exist"

# バックエンドLambda関数（test-function）のARNを取得
TEST_FUNCTION_NAME="test-function"
TEST_FUNCTION_ARN=$(aws lambda get-function \
  --function-name "$TEST_FUNCTION_NAME" \
  --endpoint-url="$ENDPOINT" \
  --query 'Configuration.FunctionArn' \
  --output text 2>/dev/null)

# メソッドの作成または更新
echo "[apigateway] creating/updating method: $HTTP_METHOD"
aws apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --authorization-type CUSTOM \
  --authorizer-id "$AUTHORIZER_ID" \
  --endpoint-url="$ENDPOINT" >/dev/null 2>/dev/null || \
aws apigateway update-method \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method "$HTTP_METHOD" \
  --patch-ops "op=replace,path=/authorizationType,value=CUSTOM" "op=replace,path=/authorizerId,value=${AUTHORIZER_ID}" \
  --endpoint-url="$ENDPOINT" >/dev/null

# 既存の統合レスポンスとメソッドレスポンスを削除（MOCK統合の残骸をクリーンアップ）
# AWS_PROXY統合を使用する場合、これらの設定は不要なため、事前に削除する
echo "[apigateway] cleaning up existing integration responses and method responses"
# 一般的なステータスコードを削除（200, 400, 500など）
for status_code in 200 400 500; do
  aws apigateway delete-integration-response \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "$HTTP_METHOD" \
    --status-code "$status_code" \
    --endpoint-url="$ENDPOINT" >/dev/null 2>/dev/null || true
  
  aws apigateway delete-method-response \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "$HTTP_METHOD" \
    --status-code "$status_code" \
    --endpoint-url="$ENDPOINT" >/dev/null 2>/dev/null || true
done
echo "[apigateway] cleanup completed"

# AWS_PROXY統合の設定
# 役割: バックエンド統合の種類と動作を定義
# 何を設定するか: Lambda関数（test-function）を呼び出す統合を設定
# AWS_PROXY統合: Lambda関数が直接HTTPレスポンスを返すため、統合レスポンス・メソッドレスポンスの設定は不要
if [ -n "$TEST_FUNCTION_ARN" ]; then
  echo "[apigateway] test-function ARN: $TEST_FUNCTION_ARN"
  
  # Lambda関数（test-function）にAPI Gatewayからの呼び出し権限を付与
  echo "[apigateway] granting invoke permission to test-function"
  aws lambda add-permission \
    --function-name "$TEST_FUNCTION_NAME" \
    --statement-id "apigateway-invoke-$(date +%s)" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:000000000000:${API_ID}/*/*" \
    --endpoint-url="$ENDPOINT" 2>/dev/null || echo "[apigateway] permission may already exist"
  
  # AWS_PROXY統合の設定（Lambda関数を呼び出す）
  echo "[apigateway] setting up AWS_PROXY integration with test-function"
  aws apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "$HTTP_METHOD" \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${TEST_FUNCTION_ARN}/invocations" \
    --endpoint-url="$ENDPOINT" >/dev/null
  
  # AWS_PROXY統合の場合、統合レスポンスとメソッドレスポンスの設定は不要
  # （Lambda関数が直接HTTPレスポンスを返すため）
  echo "[apigateway] AWS_PROXY integration configured (no response templates needed)"
else
  echo "[apigateway] WARNING: test-function not found"
  echo "[apigateway] Available Lambda functions:"
  aws lambda list-functions \
    --endpoint-url="$ENDPOINT" \
    --query 'Functions[*].FunctionName' \
    --output text 2>/dev/null || echo "[apigateway] Could not list Lambda functions"
  echo "[apigateway]"
  echo "[apigateway] test-function will be created automatically when you run 'make deploy'"
  echo "[apigateway] if lambda/test-function/function.zip exists"
  echo "[apigateway] Skipping integration setup"
fi

# 処理の流れ
# クライアントリクエスト
#    ↓
# 【Authorizer実行】authz-goが呼び出される（認証・認可）
#    ↓
# 【認証成功時のみ】メソッド（GET）が実行される
#    ↓
# 【AWS_PROXY統合】test-function Lambda関数が呼び出される
#    ↓
# クライアントレスポンス ← Lambda関数のレスポンスがそのまま返る

# APIのデプロイ
echo "[apigateway] deploying API to stage: $STAGE_NAME"
aws apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name "$STAGE_NAME" \
  --endpoint-url="$ENDPOINT" >/dev/null

# API GatewayのURLを表示
# LocalStack 4.xのエンドポイント形式: http://{api-id}.execute-api.localhost.localstack.cloud:{PORT}/{stage}/{resource-path}
LOCALSTACK_PORT="${LOCALSTACK_PORT:-4566}"
API_URL="http://${API_ID}.execute-api.localhost.localstack.cloud:${LOCALSTACK_PORT}/${STAGE_NAME}${RESOURCE_PATH}"
echo "[apigateway] API URL: $API_URL"
echo "[apigateway] Test with: curl -H 'Authorization: Bearer allow' $API_URL"

echo "[apigateway] done"

