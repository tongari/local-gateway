package testutil

import (
	"fmt"

	"github.com/google/uuid"
)

// GenerateUniqueID はプレフィックス付きのユニークIDを生成する
func GenerateUniqueID(prefix string) string {
	return fmt.Sprintf("%s_%s", prefix, uuid.New().String())
}

// TestMethodArn はテスト用のAPI Gateway Method ARNを生成する
// デフォルトで GET /resource を返す
func TestMethodArn() (string, error) {
	region, err := GetAWSRegion()
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("arn:aws:execute-api:%s:123456789012:abc123/test/GET/resource", region), nil
}

// TestMethodArnWithPath は指定したメソッドとパスでAPI Gateway Method ARNを生成する
func TestMethodArnWithPath(method, path string) (string, error) {
	region, err := GetAWSRegion()
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("arn:aws:execute-api:%s:123456789012:abc123/test/%s%s", region, method, path), nil
}
