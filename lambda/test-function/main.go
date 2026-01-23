package main

import (
	"context"
	"log"

	"github.com/aws/aws-lambda-go/lambda"
)

// Request は非Proxy統合のリクエスト形式
type Request struct {
	Body       string            `json:"body"`
	Headers    map[string]string `json:"headers"`
	HTTPMethod string            `json:"httpMethod"`
	Path       string            `json:"path"`
}

// Response は非Proxy統合のレスポンス形式
type Response struct {
	Message          string            `json:"message"`
	Status           string            `json:"status"`
	ReceivedHeaders  map[string]string `json:"receivedHeaders"`
	CompanyID        string            `json:"companyId,omitempty"`
	Scope            string            `json:"scope,omitempty"`
	InternalToken    string            `json:"internalToken,omitempty"`
	OriginalAuthHeader string          `json:"originalAuthHeader,omitempty"`
}

func handler(ctx context.Context, event Request) (Response, error) {
	log.Printf("Received event: %+v", event)
	// TODO: 本番環境ではログに出力しないこと	
	log.Printf("Headers: %+v", event.Headers)

	// ヘッダーから各値を取得
	companyID := event.Headers["X-Company-Id"]
	scope := event.Headers["X-Scope"]
	internalToken := event.Headers["X-Internal-Token"]
	originalAuth := event.Headers["Authorization"]

	response := Response{
		Message:            "Hello from test-function!",
		Status:             "success",
		ReceivedHeaders:    event.Headers,
		CompanyID:          companyID,
		Scope:              scope,
		InternalToken:      internalToken,
		OriginalAuthHeader: originalAuth,
	}

	return response, nil
}

func main() {
	lambda.Start(handler)
}
