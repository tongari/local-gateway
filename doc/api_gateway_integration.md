# API Gateway統合設定の理解

## 概要

このドキュメントでは、API Gatewayの統合設定（MOCK統合、AWS_PROXY統合）と、LocalStackでの動作について説明します。

## 統合設定の種類

### 1. MOCK統合

**役割**: バックエンド統合の種類と動作を定義

- **何を設定するか**: バックエンド（Lambda、HTTP、MOCKなど）との接続方法
- **動作**: 実際のバックエンドを呼ばずに、API Gateway内で固定レスポンスを返す
- **request-templates**: リクエストをバックエンドに渡す前に変換するテンプレート（MOCKでは使用されない）

**特徴**:
- 常に同じ固定レスポンスを返す
- バックエンド（Lambda/HTTP）は呼ばない
- テストやプロトタイプに適している

```
※現状では設定していない
```

### 2. 統合レスポンス（Integration Response）

**役割**: バックエンドからのレスポンスを処理・変換

- **何を設定するか**: 統合からの生レスポンスをクライアント向けに変換する方法
- **処理の流れ**: バックエンド → 統合レスポンス（変換） → メソッドレスポンス
- **response-templates**: レスポンスを変換するテンプレート

**注意**: AWS_PROXY統合では不要（Lambda関数が直接HTTPレスポンスを返すため）

```
※現状では設定していない（削除処理のみ実行）
既存のMOCK統合の残骸をクリーンアップするため、削除処理を実行しているが、
新規に統合レスポンスを設定することはない
```

### 3. メソッドレスポンス（Method Response）

**役割**: クライアントに返すレスポンスの「契約」を定義

- **何を設定するか**: クライアントが受け取る可能性のあるレスポンスの構造
- **処理の流れ**: 統合レスポンス → メソッドレスポンス（検証） → クライアント

**注意**: AWS_PROXY統合では不要（Lambda関数が直接HTTPレスポンスを返すため）

```
※現状では設定していない（削除処理のみ実行）
既存のMOCK統合の残骸をクリーンアップするため、削除処理を実行しているが、
新規にメソッドレスポンスを設定することはない
```

## 処理の流れ

### MOCK統合の場合

```
クライアントリクエスト
    ↓
メソッド（GET）← メソッドレスポンスで定義された形式を期待
    ↓
統合（MOCK）← 統合レスポンスで変換
    ↓
クライアントレスポンス ← メソッドレスポンスで定義された形式で返す
```

### AWS_PROXY統合の場合

```
クライアントリクエスト
    ↓
【Authorizer実行】authz-goが呼び出される（認証・認可）
    ↓
【認証成功時のみ】メソッド（GET）が実行される
    ↓
【AWS_PROXY統合】test-function Lambda関数が呼び出される
    ↓
クライアントレスポンス ← Lambda関数のレスポンスがそのまま返る
```

## curlコマンド実行時の処理フロー

```
1. クライアント（curl）からのリクエスト
   curl -H 'Authorization: Bearer allow' http://.../test/test
   
2. API Gateway（LocalStack）がリクエストを受信
   - URL: /test/test (GET)
   - ヘッダー: Authorization: Bearer allow
   
3. 【Authorizer実行】Lambda関数（authz-go）が呼び出される
   - identity-source: method.request.header.Authorization
   - Authorizationヘッダーから "Bearer allow" を取得
   - "allow" をトークンとして抽出
   - DynamoDB（AllowedTokensテーブル）でトークンを検証
     * トークンが存在し、active=true なら → Allow
     * トークンが存在しない、またはactive=false なら → Deny
   
4. 【認証成功時】AuthorizerがIAMポリシーを返す
   - Effect: "Allow"
   - PrincipalID: "user"
   - Resource: メソッドARN
   - Context: { "token": "allow" }
   
5. 【認証失敗時】AuthorizerがDenyポリシーを返す
   - Effect: "Deny"
   - API Gatewayが403 Forbiddenを返して終了（実際のAWS環境）
   
6. 【認証成功時のみ】メソッド（GET）が実行される
   - リソース: /test
   - HTTPメソッド: GET
   
7. 【AWS_PROXY統合】test-function Lambda関数が呼び出される
   - Lambda関数の実際のレスポンスが返る
   
8. クライアントにレスポンスが返る
   {
     "message": "Hello from test-function!",
     "status": "success"
   }
```

## 現在の実装

### 実装方針

現在の実装では、**AWS_PROXY統合のみ**を使用しています。MOCK統合は設定していません。

### 実装の流れ

1. **既存の統合レスポンスとメソッドレスポンスを削除**
   - MOCK統合の残骸をクリーンアップ
   - 複数のステータスコード（200, 400, 500など）を削除
   - AWS_PROXY統合では不要なため、事前に削除

2. **test-function Lambda関数のARNを取得**
   - `test-function` が存在するか確認

3. **AWS_PROXY統合を設定（test-functionが見つかった場合のみ）**
   - `test-function` Lambda関数のARNを取得
   - `test-function` にAPI Gatewayからの呼び出し権限を付与
   - `--type AWS_PROXY` でLambda関数を呼び出す統合を設定

4. **test-functionが見つからない場合**
   - 警告メッセージを表示
   - 利用可能なLambda関数の一覧を表示
   - 統合設定をスキップ（統合が設定されない状態になる）

### 実装の詳細

**統合レスポンスとメソッドレスポンスの削除**:
- AWS_PROXY統合を設定する前に、既存の設定をクリーンアップ
- ステータスコード200, 400, 500を削除
- エラーは無視（既に存在しない場合もあるため）

**AWS_PROXY統合の設定**:
- `test-function` が見つかった場合のみ実行
- 統合レスポンスとメソッドレスポンスは設定しない（不要なため）

### 実装コード（抜粋）

```bash
# 既存の統合レスポンスとメソッドレスポンスを削除（MOCK統合の残骸をクリーンアップ）
echo "[apigateway] cleaning up existing integration responses and method responses"
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

# test-function Lambda関数のARNを取得
TEST_FUNCTION_ARN=$(aws lambda get-function \
  --function-name "test-function" \
  --endpoint-url="$ENDPOINT" \
  --query 'Configuration.FunctionArn' \
  --output text 2>/dev/null)

# AWS_PROXY統合の設定（test-functionが見つかった場合のみ）
if [ -n "$TEST_FUNCTION_ARN" ]; then
  # Lambda関数にAPI Gatewayからの呼び出し権限を付与
  aws lambda add-permission \
    --function-name "test-function" \
    --statement-id "apigateway-invoke-$(date +%s)" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:000000000000:${API_ID}/*/*" \
    --endpoint-url="$ENDPOINT" 2>/dev/null || echo "[apigateway] permission may already exist"
  
  # AWS_PROXY統合の設定
  aws apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "$HTTP_METHOD" \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${TEST_FUNCTION_ARN}/invocations" \
    --endpoint-url="$ENDPOINT" >/dev/null
  
  echo "[apigateway] AWS_PROXY integration configured (no response templates needed)"
else
  echo "[apigateway] WARNING: test-function not found"
  echo "[apigateway] Skipping integration setup"
fi
```

### 注意点

- **test-functionが見つからない場合**: 統合が設定されないため、API Gatewayのメソッドに統合が存在しない状態になります。この場合、リクエストはエラーになる可能性があります。
- **統合レスポンスとメソッドレスポンス**: 削除処理のみ実行し、新規設定は行いません（AWS_PROXY統合では不要なため）。

## 統合タイプの比較

| 統合タイプ | 動作 | レスポンス | 統合レスポンス設定 | メソッドレスポンス設定 |
|-----------|------|-----------|------------------|---------------------|
| **MOCK** | バックエンドを呼ばない | 固定レスポンス（常に同じ） | 必要 | 必要 |
| **AWS_PROXY** | Lambda関数を呼び出す | Lambda関数のレスポンス（動的） | 不要 | 不要 |

## LocalStackでの動作と制限

### Authorizerの動作確認

Lambda関数（authz-go）を直接テストすると、正しく動作していることが確認できます：

**無効なトークン（TOKEN=a）の場合**:
```json
{
    "principalId": "user",
    "policyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Deny",
                "Resource": ["arn:aws:execute-api:us-east-1:000000000000:test/test/GET"]
            }
        ]
    },
    "context": {
        "reason": "token_not_found"
    }
}
```

**有効なトークン（TOKEN=allow）の場合**:
```json
{
    "principalId": "user",
    "policyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Resource": ["arn:aws:execute-api:us-east-1:000000000000:test/test/GET"]
            }
        ]
    },
    "context": {
        "token": "allow"
    }
}
```

### LocalStackの制限

**問題**: LocalStackのAPI GatewayのAuthorizer実装に問題がある可能性があります。

- **期待される動作**: AuthorizerがDenyを返す場合、API Gatewayは403 Forbiddenを返すべき
- **実際の動作（LocalStack）**: AuthorizerがDenyを返しても、API Gatewayは200 OKを返し、バックエンドが呼ばれる

**確認方法**:
```bash
# 無効なトークンで実行
make exec-curl TOKEN=a
# 期待: 403 Forbidden
# 実際（LocalStack）: 200 OK（test-functionが呼ばれる）

# 有効なトークンで実行
make exec-curl TOKEN=allow
# 期待: 200 OK（test-functionが呼ばれる）
# 実際（LocalStack）: 200 OK（test-functionが呼ばれる）
```

### Authorizerのキャッシュ設定

`authorizer-result-ttl-in-seconds` は、Authorizerの結果をキャッシュする時間を秒単位で指定します。

- **デフォルト**: 300秒（5分）
- **検証用設定**: 1秒（キャッシュの問題を排除するため）

```bash
--authorizer-result-ttl-in-seconds 1
```

## 実際のAWS環境との違い

### 実際のAWS環境での動作

**無効なトークン（TOKEN=a）の場合**:
```
TOKEN=a (無効)
  ↓
Authorizer: Denyポリシーを返す
  ↓
API Gateway: 403 Forbiddenを返す
  ↓
test-function: 呼ばれない
```

**有効なトークン（TOKEN=allow）の場合**:
```
TOKEN=allow (有効)
  ↓
Authorizer: Allowポリシーを返す
  ↓
API Gateway: リクエストを許可
  ↓
test-function: 呼ばれる → 200 OK
```

### LocalStackでの動作

**無効なトークンでも**:
```
TOKEN=a (無効)
  ↓
Authorizer: Denyポリシーを返す（正しい）
  ↓
API Gateway: 200 OKを返す（問題あり）
  ↓
test-function: 呼ばれる（本来は呼ばれるべきではない）
```

## まとめ

### 重要なポイント

1. **現在の実装**
   - **MOCK統合**: 設定していない（削除済み）
   - **AWS_PROXY統合**: 使用中（test-function Lambda関数を呼び出す）
   - **統合レスポンス**: 設定していない（削除処理のみ）
   - **メソッドレスポンス**: 設定していない（削除処理のみ）

2. **統合レスポンスとメソッドレスポンス**
   - MOCK統合: 必要（固定レスポンスを返すため）
   - AWS_PROXY統合: 不要（Lambda関数が直接HTTPレスポンスを返すため）
   - 現在の実装: 削除処理のみ実行（既存のMOCK統合の残骸をクリーンアップ）

3. **test-functionの要件**
   - `test-function` Lambda関数が存在する必要がある
   - 存在しない場合、統合が設定されず、API Gatewayのメソッドに統合が存在しない状態になる
   - `make deploy` を実行すると、`lambda/test-function/function.zip` が存在する場合、自動的にデプロイされる

4. **LocalStackの制限**
   - AuthorizerのDenyポリシーが正しく処理されない可能性がある
   - 実際のAWS環境では正しく動作するはず

5. **デプロイ手順**
   ```bash
   make clean-localstack  # 既存のリソースをクリーンアップ
   make deploy            # 再デプロイ（test-functionも含めてすべてのLambda関数をビルド＆デプロイ）
   ```

### 推奨事項

- LocalStackは開発・テスト用のツールであり、一部の機能で完全な互換性がない場合がある
- 本番環境や実際のAWS環境での動作確認が重要
- Authorizerの動作を確認する場合は、Lambda関数を直接テストする

## 参考

- [AWS API Gateway統合タイプ](https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/api-gateway-api-integration-types.html)
- [Lambda Authorizer](https://docs.aws.amazon.com/ja_jp/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [LocalStack Documentation](https://docs.localstack.cloud/)
