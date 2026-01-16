#!/bin/sh
# Lambda関数のデプロイとIAMリソースの作成
#
# このスクリプトは以下の処理を実行します：
# 1. LocalStackのヘルスチェック（最大5回リトライ）
# 2. IAM Role（lambda-authorizer-role）の作成または取得
# 3. IAM Policy（lambda-authorizer-policy）の作成または取得
#    - DynamoDBのGetItem/Query権限を付与
# 4. PolicyをRoleにアタッチ
# 5. Lambda関数のデプロイ
#    - lambda/配下のすべてのサブディレクトリを検出
#    - function.zipが存在する各ディレクトリをLambda関数としてデプロイ
#    - 既存の関数は更新、新規の関数は作成
#    - 環境変数（DynamoDBテーブル名、リージョンなど）を設定
#
# 注意: 既存のIAMリソースが存在する場合は取得し、存在しない場合は作成します。
set -eu

ENDPOINT="http://localstack:4566"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
FUNCTION_NAME="authz-go"
ROLE_NAME="lambda-authorizer-role"
POLICY_NAME="lambda-authorizer-policy"
TABLE_NAME="${ALLOWED_TOKENS_TABLE:-AllowedTokens}"

echo "[lambda] waiting for LocalStack to be ready..."
sleep 3

# LocalStackのヘルスチェック
echo "[lambda] checking LocalStack health..."
for i in 1 2 3 4 5; do
  if aws lambda list-functions --endpoint-url="$ENDPOINT" >/dev/null 2>&1; then
    echo "[lambda] LocalStack is ready"
    break
  fi
  if [ $i -eq 5 ]; then
    echo "[lambda] ERROR: LocalStack is not responding" >&2
    exit 1
  fi
  echo "[lambda] waiting for LocalStack... ($i/5)"
  sleep 2
done

# IAM Roleの作成
# Assume Role Policy Documentの作成
# Version 2012-10-17はIAMポリシー言語の標準バージョン
# 2012-10-17ってだいぶ昔から変わってないのね。
# @see https://docs.aws.amazon.com/ja_jp/IAM/latest/UserGuide/reference_policies_elements_version.html
echo "[lambda] creating IAM role: $ROLE_NAME"
echo "[lambda] DEBUG: ENDPOINT=$ENDPOINT, ROLE_NAME=$ROLE_NAME" >&2
set +e
CREATE_ROLE_OUTPUT=$(aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --endpoint-url="$ENDPOINT" \
  --query 'Role.Arn' \
  --output text 2>&1)
CREATE_ROLE_EXIT_CODE=$?
set -e

if [ $CREATE_ROLE_EXIT_CODE -eq 0 ]; then
  ROLE_ARN="$CREATE_ROLE_OUTPUT"
  echo "[lambda] role created successfully"
else
  # エラーメッセージを表示（既に存在する場合は期待されるエラー）
  echo "[lambda] create-role failed (expected if role exists): $CREATE_ROLE_OUTPUT" >&2
  set +e
  GET_ROLE_OUTPUT=$(aws iam get-role \
    --role-name "$ROLE_NAME" \
    --endpoint-url="$ENDPOINT" \
    --query 'Role.Arn' \
    --output text 2>&1)
  GET_ROLE_EXIT_CODE=$?
  set -e
  if [ $GET_ROLE_EXIT_CODE -ne 0 ]; then
    echo "[lambda] ERROR: Failed to get existing role" >&2
    echo "[lambda] create-role error: $CREATE_ROLE_OUTPUT" >&2
    echo "[lambda] get-role error: $GET_ROLE_OUTPUT" >&2
    echo "[lambda] ERROR: LocalStack might not be ready or IAM service is not available" >&2
    exit 1
  fi
  ROLE_ARN="$GET_ROLE_OUTPUT"
  echo "[lambda] using existing role"
fi

if [ -z "$ROLE_ARN" ]; then
  echo "[lambda] ERROR: ROLE_ARN is empty" >&2
  exit 1
fi

echo "[lambda] role ARN: $ROLE_ARN"

# IAM Policyの作成
echo "[lambda] creating IAM policy: $POLICY_NAME"
set +e
CREATE_POLICY_OUTPUT=$(aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [
        \"dynamodb:GetItem\",
        \"dynamodb:Query\"
      ],
      \"Resource\": \"arn:aws:dynamodb:${REGION}:000000000000:table/${TABLE_NAME}\"
    }]
  }" \
  --endpoint-url="$ENDPOINT" \
  --query 'Policy.Arn' \
  --output text 2>&1)
CREATE_POLICY_EXIT_CODE=$?
set -e

if [ $CREATE_POLICY_EXIT_CODE -eq 0 ]; then
  POLICY_ARN="$CREATE_POLICY_OUTPUT"
  echo "[lambda] policy created successfully"
else
  # エラーメッセージを表示（既に存在する場合は期待されるエラー）
  echo "[lambda] create-policy failed (expected if policy exists): $CREATE_POLICY_OUTPUT" >&2
  set +e
  LIST_POLICIES_OUTPUT=$(aws iam list-policies \
    --endpoint-url="$ENDPOINT" \
    --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
    --output text 2>&1)
  LIST_POLICIES_EXIT_CODE=$?
  set -e
  POLICY_ARN=$(echo "$LIST_POLICIES_OUTPUT" | head -n1)
  if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" = "None" ]; then
    echo "[lambda] ERROR: Failed to get existing policy" >&2
    echo "[lambda] create-policy error: $CREATE_POLICY_OUTPUT" >&2
    echo "[lambda] list-policies error: $LIST_POLICIES_OUTPUT" >&2
    exit 1
  fi
  echo "[lambda] using existing policy"
fi

if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" = "None" ]; then
  echo "[lambda] ERROR: POLICY_ARN is empty" >&2
  exit 1
fi

echo "[lambda] policy ARN: $POLICY_ARN"

# PolicyをRoleにアタッチ
echo "[lambda] attaching policy to role"
ATTACH_OUTPUT=$(aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN" \
  --endpoint-url="$ENDPOINT" 2>&1)
if [ $? -eq 0 ]; then
  echo "[lambda] policy attached successfully"
else
  # エラーメッセージを表示（既にアタッチ済みの場合は期待されるエラー）
  echo "[lambda] attach-role-policy failed (expected if already attached): $ATTACH_OUTPUT" >&2
fi

# Lambda関数のデプロイ
# lambdaフォルダ内のすべてのサブディレクトリを検出
LAMBDA_BASE_DIR="${LAMBDA_BASE_DIR:-/init/../lambda}"
echo "[lambda] discovering Lambda functions in $LAMBDA_BASE_DIR"

for lambda_dir in "$LAMBDA_BASE_DIR"/*; do
  # ディレクトリでない場合はスキップ
  [ -d "$lambda_dir" ] || continue
  
  lambda_name=$(basename "$lambda_dir")
  zip_path="$lambda_dir/function.zip"
  
  # function.zipが存在しない場合はスキップ
  if [ ! -f "$zip_path" ]; then
    echo "[lambda] skipping $lambda_name: function.zip not found"
    continue
  fi
  
  echo "[lambda] deploying Lambda function: $lambda_name"
  
  # 関数が既に存在するかチェック
  # エラーは/dev/nullに捨て、成功時のみ関数名を取得
  FUNCTION_EXISTS=$(aws lambda get-function \
    --function-name "$lambda_name" \
    --endpoint-url="$ENDPOINT" \
    --query 'Configuration.FunctionName' \
    --output text 2>/dev/null || echo "")
  
  # 環境変数の設定
  ENV_VARS="ALLOWED_TOKENS_TABLE=${TABLE_NAME},AWS_REGION=${REGION},LOCALSTACK_HOSTNAME=localstack"
  
  if [ -n "$FUNCTION_EXISTS" ] && [ "$FUNCTION_EXISTS" = "$lambda_name" ]; then
    echo "[lambda] updating existing function: $lambda_name"
    UPDATE_CODE_OUTPUT=$(aws lambda update-function-code \
      --function-name "$lambda_name" \
      --zip-file "fileb://${zip_path}" \
      --endpoint-url="$ENDPOINT" 2>&1)
    UPDATE_CODE_EXIT_CODE=$?
    if [ $UPDATE_CODE_EXIT_CODE -ne 0 ]; then
      echo "[lambda] ERROR: Failed to update function code for $lambda_name" >&2
      echo "[lambda] Error: $UPDATE_CODE_OUTPUT" >&2
      exit 1
    fi
    
    UPDATE_CONFIG_OUTPUT=$(aws lambda update-function-configuration \
      --function-name "$lambda_name" \
      --environment "Variables={${ENV_VARS}}" \
      --endpoint-url="$ENDPOINT" 2>&1)
    UPDATE_CONFIG_EXIT_CODE=$?
    if [ $UPDATE_CONFIG_EXIT_CODE -ne 0 ]; then
      echo "[lambda] ERROR: Failed to update function configuration for $lambda_name" >&2
      echo "[lambda] Error: $UPDATE_CONFIG_OUTPUT" >&2
      exit 1
    fi
  else
    echo "[lambda] creating new function: $lambda_name"
    CREATE_FUNCTION_OUTPUT=$(aws lambda create-function \
      --function-name "$lambda_name" \
      --runtime provided.al2 \
      --role "$ROLE_ARN" \
      --handler bootstrap \
      --zip-file "fileb://${zip_path}" \
      --timeout 30 \
      --environment "Variables={${ENV_VARS}}" \
      --endpoint-url="$ENDPOINT" 2>&1)
    CREATE_FUNCTION_EXIT_CODE=$?
    if [ $CREATE_FUNCTION_EXIT_CODE -ne 0 ]; then
      echo "[lambda] ERROR: Failed to create function $lambda_name" >&2
      echo "[lambda] Error: $CREATE_FUNCTION_OUTPUT" >&2
      exit 1
    fi
  fi
  
  echo "[lambda] waiting for function to be ready..."
  sleep 1
done

echo "[lambda] waiting for all functions to be ready..."
sleep 2

echo "[lambda] verifying deployed functions"
AWS_PAGER="" aws lambda list-functions \
  --endpoint-url="$ENDPOINT" \
  --query 'Functions[*].[FunctionName,Runtime,Role]' \
  --output table

echo "[lambda] done"

