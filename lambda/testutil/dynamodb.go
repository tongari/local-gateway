package testutil

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

// DefaultWaitTimeout はテーブル作成・削除の待機タイムアウト
const DefaultWaitTimeout = 30 * time.Second

// TableSchema はテーブル定義を表す
type TableSchema struct {
	TableName   string
	KeySchema   []types.KeySchemaElement
	Attributes  []types.AttributeDefinition
	BillingMode types.BillingMode
}

// NewSimpleTableSchema は単一のハッシュキーを持つシンプルなテーブルスキーマを作成
func NewSimpleTableSchema(tableName, keyName string, keyType types.ScalarAttributeType) TableSchema {
	return TableSchema{
		TableName: tableName,
		KeySchema: []types.KeySchemaElement{
			{
				AttributeName: aws.String(keyName),
				KeyType:       types.KeyTypeHash,
			},
		},
		Attributes: []types.AttributeDefinition{
			{
				AttributeName: aws.String(keyName),
				AttributeType: keyType,
			},
		},
		BillingMode: types.BillingModePayPerRequest,
	}
}

// EnsureTable はテーブルを作成し、アクティブになるまで待機する
// 既存のテーブルがあれば削除してから再作成する
func EnsureTable(ctx context.Context, client *dynamodb.Client, schema TableSchema) error {
	// 既存テーブルがあれば削除
	_, err := client.DescribeTable(ctx, &dynamodb.DescribeTableInput{
		TableName: aws.String(schema.TableName),
	})
	if err == nil {
		// テーブルが存在する場合は削除
		_, err = client.DeleteTable(ctx, &dynamodb.DeleteTableInput{
			TableName: aws.String(schema.TableName),
		})
		if err != nil {
			return fmt.Errorf("failed to delete existing table: %w", err)
		}
		// 削除完了を待機
		waiter := dynamodb.NewTableNotExistsWaiter(client)
		err = waiter.Wait(ctx, &dynamodb.DescribeTableInput{
			TableName: aws.String(schema.TableName),
		}, DefaultWaitTimeout)
		if err != nil {
			return fmt.Errorf("failed to wait for table deletion: %w", err)
		}
	}

	// テーブル作成
	billingMode := schema.BillingMode
	if billingMode == "" {
		billingMode = types.BillingModePayPerRequest
	}

	_, err = client.CreateTable(ctx, &dynamodb.CreateTableInput{
		TableName:            aws.String(schema.TableName),
		AttributeDefinitions: schema.Attributes,
		KeySchema:            schema.KeySchema,
		BillingMode:          billingMode,
	})
	if err != nil {
		return fmt.Errorf("failed to create table: %w", err)
	}

	// テーブルがアクティブになるまで待機
	waiter := dynamodb.NewTableExistsWaiter(client)
	err = waiter.Wait(ctx, &dynamodb.DescribeTableInput{
		TableName: aws.String(schema.TableName),
	}, DefaultWaitTimeout)
	if err != nil {
		return fmt.Errorf("failed to wait for table creation: %w", err)
	}

	return nil
}

// DeleteTable はテーブルを削除する（エラーは無視）
func DeleteTable(ctx context.Context, client *dynamodb.Client, tableName string) {
	client.DeleteTable(ctx, &dynamodb.DeleteTableInput{
		TableName: aws.String(tableName),
	})
}

// PutItem は汎用的なアイテム投入
func PutItem(ctx context.Context, client *dynamodb.Client, tableName string, item map[string]types.AttributeValue) error {
	_, err := client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})
	return err
}

// DeleteItem は汎用的なアイテム削除
func DeleteItem(ctx context.Context, client *dynamodb.Client, tableName string, key map[string]types.AttributeValue) error {
	_, err := client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(tableName),
		Key:       key,
	})
	return err
}
