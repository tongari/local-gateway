package testutil

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

// GetAWSRegion は環境変数からAWSリージョンを取得する
// AWS_REGION が設定されていない場合はエラーを返す
func GetAWSRegion() (string, error) {
	if region := os.Getenv("AWS_REGION"); region != "" {
		return region, nil
	}
	return "", fmt.Errorf("AWS_REGION environment variable is not set")
}

// NewDynamoDBClient はDynamoDBクライアントを返す
func NewDynamoDBClient(ctx context.Context) (*dynamodb.Client, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	return dynamodb.NewFromConfig(cfg), nil
}
