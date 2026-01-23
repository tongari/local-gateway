package main

import (
	"context"
	"fmt"
	"os"
	"testing"

	"local-gateway/lambda/testutil"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/stretchr/testify/assert"
)

const TestTableName = "AllowedTokens_Test"

var testDDBClient *dynamodb.Client
var testAuthorizer *Authorizer
var testMethodArn string

func TestMain(m *testing.M) {
	ctx := context.Background()

	// テスト用メソッドARNを取得
	var err error
	testMethodArn, err = testutil.TestMethodArn()
	if err != nil {
		fmt.Printf("Failed to get test method ARN: %v\n", err)
		os.Exit(1)
	}

	// DynamoDBクライアント作成
	testDDBClient, err = testutil.NewDynamoDBClient(ctx)
	if err != nil {
		fmt.Printf("Failed to create DynamoDB client: %v\n", err)
		os.Exit(1)
	}

	// テスト用Authorizerを作成（DIパターン）
	testAuthorizer = &Authorizer{
		TableName: TestTableName,
		DDBClient: testDDBClient,
	}

	// テスト用テーブル作成
	schema := testutil.NewSimpleTableSchema(TestTableName, "token", types.ScalarAttributeTypeS)
	if err := testutil.EnsureTable(ctx, testDDBClient, schema); err != nil {
		fmt.Printf("Failed to setup test table: %v\n", err)
		os.Exit(1)
	}

	// 全テスト実行
	code := m.Run()

	// テスト用テーブル削除
	testutil.DeleteTable(ctx, testDDBClient, TestTableName)

	os.Exit(code)
}

// ヘルパー関数: テストトークンを投入
func putTestToken(token string, active bool) error {
	ctx := context.Background()
	item := map[string]types.AttributeValue{
		"token":  &types.AttributeValueMemberS{Value: token},
		"active": &types.AttributeValueMemberBOOL{Value: active},
	}
	return testutil.PutItem(ctx, testDDBClient, TestTableName, item)
}

// ヘルパー関数: テストトークンを削除
func deleteTestToken(token string) error {
	ctx := context.Background()
	key := map[string]types.AttributeValue{
		"token": &types.AttributeValueMemberS{Value: token},
	}
	return testutil.DeleteItem(ctx, testDDBClient, TestTableName, key)
}

// ========================================
// テストケース
// ========================================

func Test_ポリシーが正しく生成されること(t *testing.T) {
	// generatePolicy は純粋関数なのでDynamoDB不要
	tests := []struct {
		name        string
		principalID string
		effect      string
		methodArn   string
		ctx         map[string]interface{}
	}{
		{
			name:        "Allowポリシーが生成されること",
			principalID: "user",
			effect:      "Allow",
			methodArn:   testMethodArn,
			ctx:         map[string]interface{}{"token": "test"},
		},
		{
			name:        "Denyポリシーが生成されること",
			principalID: "anonymous",
			effect:      "Deny",
			methodArn:   testMethodArn,
			ctx:         nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := generatePolicy(tt.principalID, tt.effect, tt.methodArn, tt.ctx)

			assert.NoError(t, err)
			assert.Equal(t, tt.principalID, resp.PrincipalID)
			assert.Equal(t, "2012-10-17", resp.PolicyDocument.Version)
			assert.Len(t, resp.PolicyDocument.Statement, 1)
			assert.Equal(t, tt.effect, resp.PolicyDocument.Statement[0].Effect)
			assert.Contains(t, resp.PolicyDocument.Statement[0].Resource, tt.methodArn)
		})
	}
}

func Test_空トークンの場合はDenyを返すこと(t *testing.T) {
	event := events.APIGatewayCustomAuthorizerRequest{
		AuthorizationToken: "",
		MethodArn:          testMethodArn,
	}

	resp, err := testAuthorizer.Handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, "anonymous", resp.PrincipalID)
	assert.Equal(t, "Deny", resp.PolicyDocument.Statement[0].Effect)
}

func Test_存在しないトークンの場合はDenyを返すこと(t *testing.T) {
	testToken := testutil.GenerateUniqueID("notfound")

	event := events.APIGatewayCustomAuthorizerRequest{
		AuthorizationToken: testToken,
		MethodArn:          testMethodArn,
	}

	resp, err := testAuthorizer.Handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, "user", resp.PrincipalID)
	assert.Equal(t, "Deny", resp.PolicyDocument.Statement[0].Effect)
	assert.Equal(t, "token_not_found", resp.Context["reason"])
}

func Test_非アクティブなトークンの場合はDenyを返すこと(t *testing.T) {
	testToken := testutil.GenerateUniqueID("inactive")
	err := putTestToken(testToken, false)
	assert.NoError(t, err)
	defer deleteTestToken(testToken)

	event := events.APIGatewayCustomAuthorizerRequest{
		AuthorizationToken: testToken,
		MethodArn:          testMethodArn,
	}

	resp, err := testAuthorizer.Handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, "user", resp.PrincipalID)
	assert.Equal(t, "Deny", resp.PolicyDocument.Statement[0].Effect)
}

func Test_有効なトークンの場合はAllowを返すこと(t *testing.T) {
	testToken := testutil.GenerateUniqueID("valid")
	err := putTestToken(testToken, true)
	assert.NoError(t, err)
	defer deleteTestToken(testToken)

	event := events.APIGatewayCustomAuthorizerRequest{
		AuthorizationToken: testToken,
		MethodArn:          testMethodArn,
	}

	resp, err := testAuthorizer.Handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, "user", resp.PrincipalID)
	assert.Equal(t, "Allow", resp.PolicyDocument.Statement[0].Effect)
	assert.Equal(t, testToken, resp.Context["token"])

	// contextにハードコードされた値が含まれることを確認
	assert.Equal(t, "12345", resp.Context["companyId"])
	assert.Equal(t, "read:stores", resp.Context["scope"])
	assert.Equal(t, "internal_abc", resp.Context["internalToken"])
}

func Test_Bearerプレフィックス付きトークンが正しく処理されること(t *testing.T) {
	// 注意: トークン自体に "bearer" を含まないようにする（除去ロジックとの競合を避ける）
	testToken := testutil.GenerateUniqueID("token")
	err := putTestToken(testToken, true)
	assert.NoError(t, err)
	defer deleteTestToken(testToken)

	tests := []struct {
		name  string
		token string
	}{
		{"Bearerスペース区切りでも認証されること", "Bearer " + testToken},
		{"bearer小文字でも認証されること", "bearer " + testToken},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			event := events.APIGatewayCustomAuthorizerRequest{
				AuthorizationToken: tt.token,
				MethodArn:          testMethodArn,
			}

			resp, err := testAuthorizer.Handler(context.Background(), event)

			assert.NoError(t, err)
			assert.Equal(t, "user", resp.PrincipalID)
			assert.Equal(t, "Allow", resp.PolicyDocument.Statement[0].Effect)
			assert.Equal(t, testToken, resp.Context["token"])
		})
	}
}
