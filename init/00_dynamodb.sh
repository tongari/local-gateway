#!/bin/sh
# DynamoDBテーブルの作成と初期データの投入
#
# このスクリプトは以下の処理を実行します：
# 1. LocalStackの起動を待機（1秒）
# 2. DynamoDBテーブル（AllowedTokens）の作成
#    - 主キー: token (String, HASH)
#    - 課金モード: PAY_PER_REQUEST
#    - 既にテーブルが存在する場合はスキップ
# 3. テーブルがアクティブになるまで待機
# 4. 初期データの投入（token: "allow"）
#    - Lambda Authorizerで使用される許可トークン
# 5. テーブル一覧の表示（確認用）
#
# 注意: 既存のテーブルが存在する場合は作成をスキップしますが、
#       初期データ（token: "allow"）は毎回投入されます（既存の場合は上書き）。
set -eu

ENDPOINT="http://localstack:4566"
TABLE="AllowedTokens"

echo "[init] waiting a bit..."
sleep 1

echo "[init] create dynamodb table (if not exists): $TABLE"

# 既にあれば何もしない
if aws dynamodb describe-table --table-name "$TABLE" --endpoint-url="$ENDPOINT" >/dev/null 2>&1; then
  echo "[init] table already exists: $TABLE"
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=token,AttributeType=S \
    --key-schema AttributeName=token,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --endpoint-url="$ENDPOINT"

  echo "[init] waiting for table active..."
  aws dynamodb wait table-exists --table-name "$TABLE" --endpoint-url="$ENDPOINT"
fi

echo "[init] seed allow token"
aws dynamodb put-item \
  --table-name "$TABLE" \
  --item '{"token":{"S":"allow"}}' \
  --endpoint-url="$ENDPOINT" >/dev/null

echo "[init] list tables"
aws dynamodb list-tables --endpoint-url="$ENDPOINT"

echo "[init] done"
