package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
)

type Response struct {
	Message     string              `json:"message"`
	Headers     map[string][]string `json:"headers"`
	Path        string              `json:"path"`
	Method      string              `json:"method"`
	ServiceName string              `json:"service_name"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func mainHandler(w http.ResponseWriter, r *http.Request) {
	serviceName := os.Getenv("SERVICE_NAME")
	if serviceName == "" {
		serviceName = "unknown"
	}

	resp := Response{
		Message:     fmt.Sprintf("Hello from %s service!", serviceName),
		Headers:     r.Header,
		Path:        r.URL.Path,
		Method:      r.Method,
		ServiceName: serviceName,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(resp)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/", mainHandler)

	log.Printf("Starting server on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
