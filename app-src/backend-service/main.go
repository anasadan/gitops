package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"
)

var (
	// Version is set at build time via -ldflags
	Version   = "dev"
	BuildTime = "unknown"
	GitCommit = "unknown"

	// Ready flag for readiness probe
	ready int32 = 0
)

type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
}

type VersionResponse struct {
	Version   string `json:"version"`
	BuildTime string `json:"build_time"`
	GitCommit string `json:"git_commit"`
	GoVersion string `json:"go_version"`
}

type InfoResponse struct {
	Service     string `json:"service"`
	Environment string `json:"environment"`
	Hostname    string `json:"hostname"`
	Message     string `json:"message"`
}

func main() {
	port := getEnv("PORT", "8080")
	serviceName := getEnv("SERVICE_NAME", "backend-service")
	environment := getEnv("ENVIRONMENT", "development")

	// Simulate startup time for realistic readiness probe behavior
	go func() {
		time.Sleep(2 * time.Second)
		atomic.StoreInt32(&ready, 1)
		log.Println("Service is ready to accept traffic")
	}()

	mux := http.NewServeMux()

	// Health check endpoint (liveness probe)
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/healthz", healthHandler)

	// Readiness probe endpoint
	mux.HandleFunc("/ready", readinessHandler)
	mux.HandleFunc("/readyz", readinessHandler)

	// Version endpoint
	mux.HandleFunc("/version", versionHandler)

	// Main API endpoint
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		infoHandler(w, serviceName, environment)
	})

	// API endpoints
	mux.HandleFunc("/api/info", func(w http.ResponseWriter, r *http.Request) {
		infoHandler(w, serviceName, environment)
	})

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      loggingMiddleware(mux),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("Starting %s on port %s (environment: %s)", serviceName, port, environment)
	log.Printf("Version: %s, Build: %s, Commit: %s", Version, BuildTime, GitCommit)

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}); err != nil {
		log.Printf("Error encoding health response: %v", err)
	}
}

func readinessHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if atomic.LoadInt32(&ready) == 1 {
		w.WriteHeader(http.StatusOK)
		if err := json.NewEncoder(w).Encode(HealthResponse{
			Status:    "ready",
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}); err != nil {
			log.Printf("Error encoding readiness response: %v", err)
		}
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		if err := json.NewEncoder(w).Encode(HealthResponse{
			Status:    "not_ready",
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}); err != nil {
			log.Printf("Error encoding readiness response: %v", err)
		}
	}
}

func versionHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(VersionResponse{
		Version:   Version,
		BuildTime: BuildTime,
		GitCommit: GitCommit,
		GoVersion: "1.21",
	}); err != nil {
		log.Printf("Error encoding version response: %v", err)
	}
}

func infoHandler(w http.ResponseWriter, serviceName, environment string) {
	hostname, _ := os.Hostname()
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(InfoResponse{
		Service:     serviceName,
		Environment: environment,
		Hostname:    hostname,
		Message:     "Welcome to the GitOps Demo API",
	}); err != nil {
		log.Printf("Error encoding info response: %v", err)
	}
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s %v", r.Method, r.URL.Path, r.RemoteAddr, time.Since(start))
	})
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}
