LAMBDA_DIR := lambda
# devcontainer内で使用する絶対パス
LAMBDA_DIR_ABS := $(CURDIR)/lambda
# dockerコンテナ内で使用するパス
LAMBDA_DIR_CONTAINER := /src/lambda
GOOS := linux
GOARCH := amd64
CGO_ENABLED := 0

LAMBDAS := $(shell find $(LAMBDA_DIR) -maxdepth 1 -mindepth 1 -type d)

# .envファイルからLOCALSTACK_PORTを読み込む（デフォルト: 4566）
LOCALSTACK_PORT := $(shell grep -E '^LOCALSTACK_PORT=' .env 2>/dev/null | sed 's/^LOCALSTACK_PORT=//' | tr -d '\n' || echo "4566")

.PHONY: all build clean deploy exec-curl exec-lambda list-lambdas get-api-id check-iam-role check-iam-policy clean-localstack help

# デフォルトターゲット（helpを表示）
.DEFAULT_GOAL := help

# コマンド一覧を表示
help:
	@echo "Available commands:"
	@echo ""
	@echo "  make all              - Lambda関数をビルドしてデプロイ"
	@echo "  make build            - Lambda関数をビルド（ZIP化まで）"
	@echo "  make deploy           - Lambda関数とAPI Gatewayをデプロイ（buildを実行前提）"
	@echo "  make clean            - Lambda関数のビルド成果物を削除"
	@echo ""
	@echo "  make list-lambdas     - LocalStackに登録されているLambda関数の一覧を表示"
	@echo "  make get-api-id       - API GatewayのIDを取得して表示"
	@echo "  make check-iam-role   - IAM Role (lambda-authorizer-role) の存在確認"
	@echo "  make check-iam-policy - IAM Policy (lambda-authorizer-policy) の存在確認"
	@echo ""
	@echo "  make exec-curl        - API Gatewayへのcurlリクエスト実行"
	@echo "                         (例: make exec-curl TOKEN=allow METHOD=GET API_PATH=/test/test)"
	@echo "  make exec-lambda      - Lambda関数を直接呼び出して実行"
	@echo "                         (例: make exec-lambda LAMBDA_NAME=test-function)"
	@echo ""
	@echo "  make clean-localstack - LocalStackリソースのクリーンアップ"
	@echo ""
	@echo "  make help             - このヘルプを表示"

all: build deploy

# Lambda関数をビルド
build:
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which go >/dev/null 2>&1; then \
	  echo "==> syncing workspace (devcontainer mode)"; \
	  go work sync; \
	  echo "==> tidying dependencies in $(LAMBDA_DIR_ABS)"; \
	  cd $(LAMBDA_DIR_ABS) && go mod tidy; \
	  for dir in $(LAMBDAS); do \
	    lambda_name=$$(basename $$dir); \
	    echo "==> building $$lambda_name"; \
	    (cd $(LAMBDA_DIR_ABS) && \
	      GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=$(CGO_ENABLED) \
	        go build -o $$lambda_name/bootstrap ./$$lambda_name && \
	      cd $$lambda_name && \
	      zip -j function.zip bootstrap); \
	  done; \
	else \
	  echo "==> syncing workspace (host mode via docker)"; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-go-dev$$"; then \
	    echo "ERROR: go-dev container (gateway-go-dev) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  docker exec gateway-go-dev go work sync; \
	  echo "==> tidying dependencies in $(LAMBDA_DIR_CONTAINER)"; \
	  docker exec gateway-go-dev sh -c "cd $(LAMBDA_DIR_CONTAINER) && go mod tidy"; \
	  for dir in $(LAMBDAS); do \
	    lambda_name=$$(basename $$dir); \
	    echo "==> building $$lambda_name"; \
	    docker exec gateway-go-dev sh -c "cd $(LAMBDA_DIR_CONTAINER) && \
	      GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=$(CGO_ENABLED) \
	        go build -o $$lambda_name/bootstrap ./$$lambda_name && \
	      cd $$lambda_name && \
	      zip -j function.zip bootstrap"; \
	  done; \
	fi
# Lambda関数のビルド成果物を削除
clean:
	@find $(LAMBDA_DIR) -name bootstrap -o -name function.zip | xargs rm -f

# LocalStackに登録されているLambda関数の一覧を表示
list-lambdas:
	@echo "==> listing Lambda functions"
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	  echo "Using AWS CLI directly (devcontainer mode)"; \
	  AWS_PAGER="" aws lambda list-functions \
	    --endpoint-url=http://localstack:4566 \
	    --output table || exit 1; \
	else \
	  echo "Using docker exec (host mode)"; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	    echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  docker exec gateway-awscli aws lambda list-functions \
	    --endpoint-url=http://localstack:4566 \
	    --output table || exit 1; \
	fi

# API GatewayのIDを取得して表示
get-api-id:
	@echo "==> getting API Gateway ID"
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	  echo "Using AWS CLI directly (devcontainer mode)"; \
	  API_ID=$$(AWS_PAGER="" aws apigateway get-rest-apis \
	    --endpoint-url=http://localstack:4566 \
	    --query "items[?name=='local-gateway-api'].id | [0]" \
	    --output text 2>/dev/null); \
	  if [ -z "$$API_ID" ]; then \
	    echo "ERROR: API Gateway 'local-gateway-api' not found."; \
	    echo "Available APIs:"; \
	    AWS_PAGER="" aws apigateway get-rest-apis \
	      --endpoint-url=http://localstack:4566 \
	      --query "items[*].[name,id]" \
	      --output table 2>/dev/null || echo "  (Could not list APIs)"; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  else \
	    echo "API ID: $$API_ID"; \
	  fi; \
	else \
	  echo "Using docker exec (host mode)"; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	    echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  API_ID=$$(docker exec gateway-awscli aws apigateway get-rest-apis \
	    --endpoint-url=http://localstack:4566 \
	    --query "items[?name=='local-gateway-api'].id | [0]" \
	    --output text 2>/dev/null); \
	  if [ -z "$$API_ID" ]; then \
	    echo "ERROR: API Gateway 'local-gateway-api' not found."; \
	    echo "Available APIs:"; \
	    docker exec gateway-awscli aws apigateway get-rest-apis \
	      --endpoint-url=http://localstack:4566 \
	      --query "items[*].[name,id]" \
	      --output table 2>/dev/null || echo "  (Could not list APIs)"; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  else \
	    echo "API ID: $$API_ID"; \
	  fi; \
	fi

# IAM Roleの存在確認
check-iam-role:
	@echo "==> checking IAM Role: lambda-authorizer-role"
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	  echo "Using AWS CLI directly (devcontainer mode)"; \
	  ROLE_OUTPUT=$$(AWS_PAGER="" aws iam get-role \
	    --role-name lambda-authorizer-role \
	    --endpoint-url=http://localstack:4566 \
	    2>&1); \
	  ROLE_EXIT_CODE=$$?; \
	  if [ $$ROLE_EXIT_CODE -eq 0 ]; then \
	    echo "IAM Role exists:"; \
	    echo "$$ROLE_OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$$ROLE_OUTPUT"; \
	    echo ""; \
	    echo "Attached policies:"; \
	    AWS_PAGER="" aws iam list-attached-role-policies \
	      --role-name lambda-authorizer-role \
	      --endpoint-url=http://localstack:4566 \
	      --output table 2>&1 || echo "  (Could not list attached policies)"; \
	  else \
	    echo "ERROR: IAM Role 'lambda-authorizer-role' not found."; \
	    echo "Error details:"; \
	    echo "$$ROLE_OUTPUT"; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  fi; \
	else \
	  echo "Using docker exec (host mode)"; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	    echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  ROLE_OUTPUT=$$(docker exec gateway-awscli aws iam get-role \
	    --role-name lambda-authorizer-role \
	    --endpoint-url=http://localstack:4566 \
	    2>&1); \
	  ROLE_EXIT_CODE=$$?; \
	  if [ $$ROLE_EXIT_CODE -eq 0 ]; then \
	    echo "IAM Role exists:"; \
	    echo "$$ROLE_OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$$ROLE_OUTPUT"; \
	    echo ""; \
	    echo "Attached policies:"; \
	    docker exec gateway-awscli aws iam list-attached-role-policies \
	      --role-name lambda-authorizer-role \
	      --endpoint-url=http://localstack:4566 \
	      --output table 2>&1 || echo "  (Could not list attached policies)"; \
	  else \
	    echo "ERROR: IAM Role 'lambda-authorizer-role' not found."; \
	    echo "Error details:"; \
	    echo "$$ROLE_OUTPUT"; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  fi; \
	fi

# IAM Policyの存在確認
check-iam-policy:
	@echo "==> checking IAM Policy: lambda-authorizer-policy"
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	  echo "Using AWS CLI directly (devcontainer mode)"; \
	  POLICY_ARN=$$(AWS_PAGER="" aws iam list-policies \
	    --endpoint-url=http://localstack:4566 \
	    --query "Policies[?PolicyName=='lambda-authorizer-policy'].Arn" \
	    --output text 2>&1 | head -n1); \
	  if [ -n "$$POLICY_ARN" ] && [ "$$POLICY_ARN" != "None" ]; then \
	    echo "IAM Policy exists:"; \
	    echo "Policy ARN: $$POLICY_ARN"; \
	    echo ""; \
	    echo "Policy document:"; \
	    AWS_PAGER="" aws iam get-policy \
	      --policy-arn "$$POLICY_ARN" \
	      --endpoint-url=http://localstack:4566 \
	      --output json 2>&1 | python3 -m json.tool 2>/dev/null || \
	    AWS_PAGER="" aws iam get-policy \
	      --policy-arn "$$POLICY_ARN" \
	      --endpoint-url=http://localstack:4566 \
	      --output json 2>&1; \
	  else \
	    echo "ERROR: IAM Policy 'lambda-authorizer-policy' not found."; \
	    echo "Available policies:"; \
	    AWS_PAGER="" aws iam list-policies \
	      --endpoint-url=http://localstack:4566 \
	      --query "Policies[*].[PolicyName,Arn]" \
	      --output table 2>&1 || echo "  (Could not list policies)"; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  fi; \
	else \
	  echo "Using docker exec (host mode)"; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	    echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  POLICY_ARN=$$(docker exec gateway-awscli aws iam list-policies \
	    --endpoint-url=http://localstack:4566 \
	    --query "Policies[?PolicyName=='lambda-authorizer-policy'].Arn" \
	    --output text 2>&1 | head -n1); \
	  if [ -n "$$POLICY_ARN" ] && [ "$$POLICY_ARN" != "None" ]; then \
	    echo "IAM Policy exists:"; \
	    echo "Policy ARN: $$POLICY_ARN"; \
	    echo ""; \
	    echo "Policy document:"; \
	    docker exec gateway-awscli aws iam get-policy \
	      --policy-arn "$$POLICY_ARN" \
	      --endpoint-url=http://localstack:4566 \
	      --output json 2>&1 | python3 -m json.tool 2>/dev/null || \
	    docker exec gateway-awscli aws iam get-policy \
	      --policy-arn "$$POLICY_ARN" \
	      --endpoint-url=http://localstack:4566 \
	      --output json 2>&1; \
	  else \
	    echo "ERROR: IAM Policy 'lambda-authorizer-policy' not found."; \
	    echo "Available policies:"; \
	    docker exec gateway-awscli aws iam list-policies \
	      --endpoint-url=http://localstack:4566 \
	      --query "Policies[*].[PolicyName,Arn]" \
	      --output table 2>&1 || echo "  (Could not list policies)"; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  fi; \
	fi

# Lambda関数とAPI Gatewayのデプロイ（LocalStackが起動している必要がある）
deploy: build
	@echo "==> deploying Lambda function and API Gateway"
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	  echo "Deploying (devcontainer mode)..."; \
	  echo "Deploying Lambda function..."; \
	  LAMBDA_BASE_DIR="$(LAMBDA_DIR_ABS)" /bin/sh "$(CURDIR)/init/01_lambda.sh" 2>&1 || \
	    (echo "ERROR: Lambda deployment failed."; exit 1); \
	  echo "Deploying API Gateway..."; \
	  /bin/sh "$(CURDIR)/init/02_api_gateway.sh" 2>&1 || \
	    (echo "ERROR: API Gateway deployment failed."; exit 1); \
	else \
	  echo "Deploying (host mode via docker)..."; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	    echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  echo "Deploying Lambda function..."; \
	  docker exec gateway-awscli /bin/sh -c "/init/01_lambda.sh" 2>&1 || \
	    (echo "ERROR: Lambda deployment failed. Check logs with 'docker compose logs awscli'"; exit 1); \
	  echo "Deploying API Gateway..."; \
	  docker exec gateway-awscli /bin/sh -c "/init/02_api_gateway.sh" 2>&1 || \
	    (echo "ERROR: API Gateway deployment failed. Check logs with 'docker compose logs awscli'"; exit 1); \
	fi
	@echo "==> Deployment completed successfully"

# API Gatewayへのcurlリクエスト実行（引数で柔軟に指定可能）
# ポート番号は.envのLOCALSTACK_PORTが使用される（デフォルト: 4566）
# API GatewayのIDは自動取得される（local-gateway-apiを検索）
# 使用例: make exec-curl                                    # デフォルト設定で実行
# 使用例: make exec-curl TOKEN=allow                       # 有効なトークンで実行
# 使用例: make exec-curl TOKEN=invalid-token               # 無効なトークンで実行
# 使用例: make exec-curl METHOD=POST API_PATH=/test/other      # メソッドとパスを指定
# 使用例: make exec-curl TOKEN=allow METHOD=GET API_PATH=/test/test
exec-curl:
	@echo "==> testing API Gateway with curl"
	@if [ -z "$(API_ID)" ]; then \
	  if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	    echo "Getting API ID from LocalStack (devcontainer mode)..."; \
	    API_ID=$$(AWS_PAGER="" aws apigateway get-rest-apis \
	      --endpoint-url=http://localstack:4566 \
	      --query "items[?name=='local-gateway-api'].id | [0]" \
	      --output text 2>/dev/null); \
	  else \
	    echo "Checking if containers are running..."; \
	    if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	      echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	      exit 1; \
	    fi; \
	    echo "Getting API ID from LocalStack (host mode)..."; \
	    API_ID=$$(docker exec gateway-awscli aws apigateway get-rest-apis \
	      --endpoint-url=http://localstack:4566 \
	      --query "items[?name=='local-gateway-api'].id | [0]" \
	      --output text 2>/dev/null); \
	  fi; \
	  if [ -z "$$API_ID" ]; then \
	    echo "ERROR: API Gateway 'local-gateway-api' not found."; \
	    echo "Available APIs:"; \
	    if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	      AWS_PAGER="" aws apigateway get-rest-apis \
	        --endpoint-url=http://localstack:4566 \
	        --query "items[*].[name,id]" \
	        --output table 2>/dev/null || echo "  (Could not list APIs)"; \
	    else \
	      docker exec gateway-awscli aws apigateway get-rest-apis \
	        --endpoint-url=http://localstack:4566 \
	        --query "items[*].[name,id]" \
	        --output table 2>/dev/null || echo "  (Could not list APIs)"; \
	    fi; \
	    echo ""; \
	    echo "Try running: make deploy"; \
	    exit 1; \
	  fi; \
	else \
	  API_ID="$(API_ID)"; \
	fi; \
	PORT=$${PORT:-$(LOCALSTACK_PORT)}; \
	METHOD=$${METHOD:-GET}; \
	API_PATH=$${API_PATH:-/test/test}; \
	API_URL="http://$$API_ID.execute-api.localhost.localstack.cloud:$$PORT$$API_PATH"; \
	echo "API ID: $$API_ID"; \
	echo "Port: $$PORT (from .env LOCALSTACK_PORT: $(LOCALSTACK_PORT))"; \
	echo "Method: $$METHOD"; \
	echo "Path: $$API_PATH"; \
	echo "API URL: $$API_URL"; \
	echo ""; \
	if [ -n "$(TOKEN)" ]; then \
	  echo "Test: Request with token '$(TOKEN)'"; \
	  curl -s -w "\nHTTP Status: %{http_code}\n" -X $$METHOD $$API_URL \
	    -H "Authorization: Bearer $(TOKEN)" || true; \
	else \
	  echo "Test: Request without token"; \
	  curl -s -w "\nHTTP Status: %{http_code}\n" -X $$METHOD $$API_URL || true; \
	fi


# Lambda関数を直接呼び出して実行（引数で関数名を指定）
# 使用例: make exec-lambda LAMBDA_NAME=test-function
# 使用例: make exec-lambda LAMBDA_NAME=authz-go PAYLOAD='{"type":"TOKEN","authorizationToken":"Bearer allow","methodArn":"arn:aws:execute-api:us-east-1:000000000000:test/test/GET"}'
exec-lambda:
	@if [ -z "$(LAMBDA_NAME)" ]; then \
	  echo "ERROR: LAMBDA_NAME is required"; \
	  echo "Usage: make exec-lambda LAMBDA_NAME=<function-name> [PAYLOAD='<json-payload>']"; \
	  echo ""; \
	  echo "Examples:"; \
	  echo "  make exec-lambda LAMBDA_NAME=test-function"; \
	  echo "  make exec-lambda LAMBDA_NAME=authz-go PAYLOAD='{\"type\":\"TOKEN\",\"authorizationToken\":\"Bearer allow\",\"methodArn\":\"arn:aws:execute-api:us-east-1:000000000000:test/test/GET\"}'"; \
	  exit 1; \
	fi
	@echo "==> executing Lambda function: $(LAMBDA_NAME)"
	@if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	  echo "Using AWS CLI directly (devcontainer mode)"; \
	  if [ -z "$(PAYLOAD)" ]; then \
	    echo "[exec-lambda] Using default API Gateway Proxy Request payload"; \
	    echo '{"httpMethod":"GET","path":"/$(LAMBDA_NAME)","headers":{},"body":null,"isBase64Encoded":false}' > /tmp/test-payload.json; \
	  else \
	    echo "[exec-lambda] Using custom payload"; \
	    echo '$(PAYLOAD)' > /tmp/test-payload.json; \
	  fi; \
	  AWS_PAGER="" aws lambda invoke \
	    --function-name "$(LAMBDA_NAME)" \
	    --cli-binary-format raw-in-base64-out \
	    --payload file:///tmp/test-payload.json \
	    --endpoint-url=http://localstack:4566 \
	    /tmp/test-response.json && \
	  echo "" && \
	  echo "Response:" && \
	  cat /tmp/test-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/test-response.json && \
	  echo ""; \
	else \
	  echo "Using docker exec (host mode)"; \
	  echo "Checking if containers are running..."; \
	  if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^gateway-awscli$$"; then \
	    echo "ERROR: awscli container (gateway-awscli) is not running. Run 'docker compose up -d' first."; \
	    exit 1; \
	  fi; \
	  if [ -z "$(PAYLOAD)" ]; then \
	    echo "[exec-lambda] Using default API Gateway Proxy Request payload"; \
	    docker exec gateway-awscli /bin/sh -c "echo '{\"httpMethod\":\"GET\",\"path\":\"/$(LAMBDA_NAME)\",\"headers\":{},\"body\":null,\"isBase64Encoded\":false}' > /tmp/test-payload.json"; \
	  else \
	    echo "[exec-lambda] Using custom payload"; \
	    echo '$(PAYLOAD)' > /tmp/test-lambda-payload.json && \
	    docker cp /tmp/test-lambda-payload.json gateway-awscli:/tmp/test-payload.json && \
	    rm -f /tmp/test-lambda-payload.json; \
	  fi; \
	  docker exec gateway-awscli aws lambda invoke \
	    --function-name "$(LAMBDA_NAME)" \
	    --cli-binary-format raw-in-base64-out \
	    --payload file:///tmp/test-payload.json \
	    --endpoint-url=http://localstack:4566 \
	    /tmp/test-response.json && \
	  echo "" && \
	  echo "Response:" && \
	  docker exec gateway-awscli cat /tmp/test-response.json | python3 -m json.tool 2>/dev/null || docker exec gateway-awscli cat /tmp/test-response.json && \
	  echo ""; \
	fi

# LocalStackリソースのクリーンアップ
clean-localstack:
	@echo "==> cleaning up LocalStack resources"
	@echo "WARNING: This will delete all resources in LocalStack"
	@printf "Are you sure? [y/N] "; \
	read REPLY; \
	case "$$REPLY" in \
	  [Yy]*) \
	    if [ "$$IS_DEV_CONTAINER" = "true" ] && which aws >/dev/null 2>&1; then \
	    echo "Using AWS CLI directly (devcontainer mode)"; \
	    /bin/sh -c "\
	      echo '[cleanup] deleting Lambda functions...'; \
	      FUNCTIONS=\$$(AWS_PAGER=\"\" aws lambda list-functions --endpoint-url=http://localstack:4566 --query 'Functions[*].FunctionName' --output text 2>/dev/null || echo ''); \
	      if [ -n \"\$$FUNCTIONS\" ]; then \
	        for func in \$$FUNCTIONS; do \
	          echo \"[cleanup] deleting Lambda function: \$$func\"; \
	          AWS_PAGER=\"\" aws lambda delete-function --function-name \"\$$func\" --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	        done; \
	      else \
	        echo '[cleanup] no Lambda functions found'; \
	      fi; \
	      echo '[cleanup] deleting IAM resources...'; \
	      AWS_PAGER=\"\" aws iam detach-role-policy --role-name lambda-authorizer-role --policy-arn \$$(AWS_PAGER=\"\" aws iam list-policies --endpoint-url=http://localstack:4566 --query \"Policies[?PolicyName=='lambda-authorizer-policy'].Arn\" --output text | head -n1) --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      AWS_PAGER=\"\" aws iam delete-role --role-name lambda-authorizer-role --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      AWS_PAGER=\"\" aws iam delete-policy --policy-arn \$$(AWS_PAGER=\"\" aws iam list-policies --endpoint-url=http://localstack:4566 --query \"Policies[?PolicyName=='lambda-authorizer-policy'].Arn\" --output text | head -n1) --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      echo '[cleanup] deleting API Gateway...'; \
	      API_ID=\$$(AWS_PAGER=\"\" aws apigateway get-rest-apis --endpoint-url=http://localstack:4566 --query \"items[?name=='local-gateway-api'].id | [0]\" --output text); \
	      if [ -n \"\$$API_ID\" ]; then \
	        AWS_PAGER=\"\" aws apigateway delete-rest-api --rest-api-id \$$API_ID --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      fi; \
	      echo '[cleanup] Cleanup completed'"; \
	  else \
	    echo "Using docker exec (host mode)"; \
	    docker exec gateway-awscli /bin/sh -c "\
	      echo '[cleanup] deleting Lambda functions...'; \
	      FUNCTIONS=\$$(aws lambda list-functions --endpoint-url=http://localstack:4566 --query 'Functions[*].FunctionName' --output text 2>/dev/null || echo ''); \
	      if [ -n \"\$$FUNCTIONS\" ]; then \
	        for func in \$$FUNCTIONS; do \
	          echo \"[cleanup] deleting Lambda function: \$$func\"; \
	          aws lambda delete-function --function-name \"\$$func\" --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	        done; \
	      else \
	        echo '[cleanup] no Lambda functions found'; \
	      fi; \
	      echo '[cleanup] deleting IAM resources...'; \
	      aws iam detach-role-policy --role-name lambda-authorizer-role --policy-arn \$$(aws iam list-policies --endpoint-url=http://localstack:4566 --query \"Policies[?PolicyName=='lambda-authorizer-policy'].Arn\" --output text | head -n1) --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      aws iam delete-role --role-name lambda-authorizer-role --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      aws iam delete-policy --policy-arn \$$(aws iam list-policies --endpoint-url=http://localstack:4566 --query \"Policies[?PolicyName=='lambda-authorizer-policy'].Arn\" --output text | head -n1) --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      echo '[cleanup] deleting API Gateway...'; \
	      API_ID=\$$(aws apigateway get-rest-apis --endpoint-url=http://localstack:4566 --query \"items[?name=='local-gateway-api'].id | [0]\" --output text); \
	      if [ -n \"\$$API_ID\" ]; then \
	        aws apigateway delete-rest-api --rest-api-id \$$API_ID --endpoint-url=http://localstack:4566 2>/dev/null || true; \
	      fi; \
	      echo '[cleanup] Cleanup completed'" || echo "ERROR: Container not running"; \
	    fi \
	    ;; \
	  *) \
	    echo "Cancelled" \
	    ;; \
	esac
