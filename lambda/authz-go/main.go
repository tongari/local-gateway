package main

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

const DefaultTableName = "AllowedTokens"

// Authorizer はトークン認証を行うLambda Authorizerの構造体
type Authorizer struct {
	TableName string
	DDBClient *dynamodb.Client
}

// NewAuthorizer はAuthorizerを作成する
// DynamoDBのエンドポイントは環境変数 AWS_ENDPOINT_URL_DYNAMODB で設定可能（LocalStack用）
func NewAuthorizer(ctx context.Context) (*Authorizer, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	return &Authorizer{
		TableName: DefaultTableName,
		DDBClient: dynamodb.NewFromConfig(cfg),
	}, nil
}

func generatePolicy(principalID, effect, methodArn string, ctx map[string]interface{}) (events.APIGatewayCustomAuthorizerResponse, error) {
	return events.APIGatewayCustomAuthorizerResponse{
		PrincipalID: principalID,
		PolicyDocument: events.APIGatewayCustomAuthorizerPolicy{
			Version: "2012-10-17",
			Statement: []events.IAMPolicyStatement{
				{
					Action:   []string{"execute-api:Invoke"},
					Effect:   effect,
					Resource: []string{methodArn},
				},
			},
		},
		Context: ctx,
	}, nil
}

// Handler はAPIGateway Lambda Authorizerのハンドラ
func (a *Authorizer) Handler(ctx context.Context, event events.APIGatewayCustomAuthorizerRequest) (events.APIGatewayCustomAuthorizerResponse, error) {
	raw := strings.TrimSpace(event.AuthorizationToken)
	// WARNING: 本番環境では機密情報をログに出力しないこと
	// 開発/検証用のダミートークンのみ使用する前提でログ出力しています
	// 本番移植時は log.Printf("[Authorizer] Token received (length: %d)", len(raw)) に変更してください
	log.Printf("[Authorizer] Received token: %q", raw)

	// "Bearer " プレフィックスを除去
	token := strings.TrimSpace(strings.TrimPrefix(raw, "Bearer"))
	token = strings.TrimSpace(strings.TrimPrefix(token, "bearer"))
	token = strings.TrimSpace(token)
	// WARNING: 本番環境では機密情報をログに出力しないこと
	// 本番移植時はこの行を削除するか、log.Printf("[Authorizer] Token extracted (length: %d)", len(token)) に変更してください
	log.Printf("[Authorizer] Extracted token: %q", token)

	if token == "" {
		log.Printf("[Authorizer] Token is empty, returning Deny")
		return generatePolicy("anonymous", "Deny", event.MethodArn, nil)
	}

	out, err := a.DDBClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(a.TableName),
		Key: map[string]types.AttributeValue{
			"token": &types.AttributeValueMemberS{Value: token},
		},
		// 結果整合性で十分（コスト削減: 読み取りコスト半減）
		// 本番環境で強整合性が必要な場合は aws.Bool(true) に変更
		ConsistentRead: aws.Bool(false),
	})
	if err != nil {
		log.Printf("[Authorizer] DynamoDB GetItem error: %v", err)
		return generatePolicy("user", "Deny", event.MethodArn, map[string]interface{}{
			"error": "ddb_get_failed",
		})
	}

	if out.Item == nil {
		log.Printf("[Authorizer] Token not found in DynamoDB, returning Deny")
		return generatePolicy("user", "Deny", event.MethodArn, map[string]interface{}{
			"reason": "token_not_found",
		})
	}

	log.Printf("[Authorizer] Token found in DynamoDB, checking active status")
	if v, ok := out.Item["active"].(*types.AttributeValueMemberBOOL); ok && v.Value == false {
		log.Printf("[Authorizer] Token is inactive, returning Deny")
		return generatePolicy("user", "Deny", event.MethodArn, nil)
	}

	log.Printf("[Authorizer] Token is valid, returning Allow")

	// Contextに追加情報を含める
	// TODO: 本番環境ではDynamoDBから取得するように変更
	authContext := map[string]interface{}{
		"token":         token, // WARNING: 本番環境では削除
		"companyId":     "12345",
		"scope":         "read:stores",
		"internalToken": "internal_abc",
	}


	return generatePolicy("user", "Allow", event.MethodArn, authContext)
}

func main() {
	ctx := context.Background()
	auth, err := NewAuthorizer(ctx)
	if err != nil {
		log.Fatalf("Failed to initialize authorizer: %v", err)
	}
	lambda.Start(auth.Handler)
}
