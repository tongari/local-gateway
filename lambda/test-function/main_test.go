package main

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_非Proxy形式のリクエストを正しく処理できること(t *testing.T) {
	event := Request{
		Body: "",
		Headers: map[string]string{
			"X-Company-Id":    "12345",
			"X-Scope":         "read:stores",
			"X-Internal-Token": "Bearer internal_abc",
			"Authorization":   "Bearer original_token",
		},
		HTTPMethod: "GET",
		Path:       "/test",
	}

	resp, err := handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, "Hello from test-function!", resp.Message)
	assert.Equal(t, "success", resp.Status)

	// ヘッダーが正しく取得されていること
	assert.Equal(t, "12345", resp.CompanyID)
	assert.Equal(t, "read:stores", resp.Scope)
	assert.Equal(t, "Bearer internal_abc", resp.InternalToken)
	assert.Equal(t, "Bearer original_token", resp.OriginalAuthHeader)

	// ReceivedHeadersに全ヘッダーが含まれること
	assert.Equal(t, "12345", resp.ReceivedHeaders["X-Company-Id"])
	assert.Equal(t, "read:stores", resp.ReceivedHeaders["X-Scope"])
	assert.Equal(t, "Bearer internal_abc", resp.ReceivedHeaders["X-Internal-Token"])
	assert.Equal(t, "Bearer original_token", resp.ReceivedHeaders["Authorization"])
}

func Test_ヘッダーがない場合でもエラーにならないこと(t *testing.T) {
	event := Request{
		Body:       "",
		Headers:    map[string]string{},
		HTTPMethod: "GET",
		Path:       "/test",
	}

	resp, err := handler(context.Background(), event)

	assert.NoError(t, err)
	assert.Equal(t, "Hello from test-function!", resp.Message)
	assert.Equal(t, "success", resp.Status)

	// ヘッダーが空の場合は空文字列が返ること
	assert.Empty(t, resp.CompanyID)
	assert.Empty(t, resp.Scope)
	assert.Empty(t, resp.InternalToken)
}

func Test_マッピングテンプレートから渡されるヘッダーを処理できること(t *testing.T) {
	// API Gatewayのマッピングテンプレートから渡される形式をシミュレート
	event := Request{
		Body: "",
		Headers: map[string]string{
			"Host":              "api.example.com",
			"User-Agent":        "curl/7.64.1",
			"Accept":            "*/*",
			"X-Company-Id":      "12345",
			"X-Scope":           "read:stores",
			"X-Internal-Token":  "Bearer internal_abc",
			"Authorization":     "Bearer original_token",
			"X-Amzn-Trace-Id":   "Root=1-123456",
			"X-Forwarded-For":   "192.168.1.1",
			"X-Forwarded-Port":  "443",
			"X-Forwarded-Proto": "https",
		},
		HTTPMethod: "GET",
		Path:       "/test/test",
	}

	resp, err := handler(context.Background(), event)

	assert.NoError(t, err)

	// カスタムヘッダーが正しく処理されること
	assert.Equal(t, "12345", resp.CompanyID)
	assert.Equal(t, "read:stores", resp.Scope)
	assert.Equal(t, "Bearer internal_abc", resp.InternalToken)
	assert.Equal(t, "Bearer original_token", resp.OriginalAuthHeader)

	// すべてのヘッダーがReceivedHeadersに含まれること
	assert.NotEmpty(t, resp.ReceivedHeaders)
	assert.Contains(t, resp.ReceivedHeaders, "Host")
	assert.Contains(t, resp.ReceivedHeaders, "X-Company-Id")
	assert.Contains(t, resp.ReceivedHeaders, "X-Internal-Token")
	assert.Contains(t, resp.ReceivedHeaders, "Authorization")
}
