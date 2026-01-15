package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

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

func handler(ctx context.Context, event events.APIGatewayCustomAuthorizerRequest) (events.APIGatewayCustomAuthorizerResponse, error) {
	raw := strings.TrimSpace(event.AuthorizationToken)
	log.Printf("[Authorizer] Received token: %q", raw)
	
	// "Bearer " プレフィックスを除去
	token := strings.TrimSpace(strings.TrimPrefix(raw, "Bearer"))
	token = strings.TrimSpace(strings.TrimPrefix(token, "bearer"))
	token = strings.TrimSpace(token)
	log.Printf("[Authorizer] Extracted token: %q", token)

	if token == "" {
		log.Printf("[Authorizer] Token is empty, returning Deny")
		return generatePolicy("anonymous", "Deny", event.MethodArn, nil)
	}

	table := os.Getenv("ALLOWED_TOKENS_TABLE")
	if table == "" {
		table = "AllowedTokens"
	}

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	// LocalStack環境用のDynamoDBエンドポイント設定
	// Lambda関数がLocalStack内で実行されるため、通常のAWSエンドポイントではなく
	// LocalStackのエンドポイント（http://localstack:4566）を使用する
	host := os.Getenv("LOCALSTACK_HOSTNAME")
	if host == "" {
		host = "localhost"
	}
	endpoint := fmt.Sprintf("http://%s:4566", host)

	cfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion(region),
		config.WithEndpointResolverWithOptions(
			aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
				if service == dynamodb.ServiceID {
					return aws.Endpoint{URL: endpoint, SigningRegion: region}, nil
				}
				return aws.Endpoint{}, &aws.EndpointNotFoundError{}
			}),
		),
	)
	if err != nil {
		return generatePolicy("user", "Deny", event.MethodArn, map[string]interface{}{
			"error": "config_load_failed",
		})
	}

	ddb := dynamodb.NewFromConfig(cfg)

	out, err := ddb.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(table),
		Key: map[string]types.AttributeValue{
			"token": &types.AttributeValueMemberS{Value: token},
		},
		ConsistentRead: aws.Bool(true),
	})
	if err != nil {
		return generatePolicy("user", "Deny", event.MethodArn, map[string]interface{}{
			"error": "ddb_get_failed",
		})
	}

	if out.Item == nil {
		// トークンがDynamoDBに存在しない場合はDeny
		log.Printf("[Authorizer] Token not found in DynamoDB, returning Deny")
		return generatePolicy("user", "Deny", event.MethodArn, map[string]interface{}{
			"reason": "token_not_found",
		})
	}

	log.Printf("[Authorizer] Token found in DynamoDB, checking active status")
	// active が false なら拒否、未設定なら許可扱い
	if v, ok := out.Item["active"].(*types.AttributeValueMemberBOOL); ok && v.Value == false {
		log.Printf("[Authorizer] Token is inactive, returning Deny")
		return generatePolicy("user", "Deny", event.MethodArn, nil)
	}

	log.Printf("[Authorizer] Token is valid, returning Allow")
	return generatePolicy("user", "Allow", event.MethodArn, map[string]interface{}{
		"token": token,
	})
}

func main() {
	lambda.Start(handler)
}
