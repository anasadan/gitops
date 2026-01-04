.PHONY: help bootstrap clusters argocd build deploy clean test lint

# Default target
help:
	@echo "GitOps Kubernetes Platform - Available Commands"
	@echo ""
	@echo "Setup & Infrastructure:"
	@echo "  make bootstrap    - Full environment setup (clusters + ArgoCD + deploy)"
	@echo "  make clusters     - Create K3D clusters only"
	@echo "  make argocd       - Install ArgoCD on dev cluster"
	@echo "  make clean        - Delete all clusters and cleanup"
	@echo ""
	@echo "Development:"
	@echo "  make build        - Build Docker image locally"
	@echo "  make push         - Build and push to local registry"
	@echo "  make deploy       - Deploy to dev cluster"
	@echo "  make test         - Run Go tests"
	@echo "  make lint         - Run linters"
	@echo ""
	@echo "Deployment:"
	@echo "  make promote-staging  - Promote dev to staging"
	@echo "  make promote-prod     - Promote staging to production"
	@echo "  make status           - Show deployment status"
	@echo ""
	@echo "Monitoring:"
	@echo "  make health       - Run health checks"
	@echo "  make logs         - Show application logs"
	@echo "  make port-forward - Port forward to dev application"
	@echo ""

# Setup targets
bootstrap:
	@./scripts/setup/bootstrap.sh full

clusters:
	@./scripts/setup/create-clusters.sh create-all

argocd:
	@./scripts/setup/install-argocd.sh all

clean:
	@./scripts/setup/bootstrap.sh cleanup

# Build targets
build:
	@docker build -t gitops-demo:local \
		-f app-src/backend-service/Dockerfile \
		--build-arg VERSION=local \
		--build-arg BUILD_TIME=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		--build-arg GIT_COMMIT=$$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown') \
		app-src/backend-service

push: build
	@docker tag gitops-demo:local localhost:5050/gitops-demo:latest
	@docker push localhost:5050/gitops-demo:latest

deploy:
	@./scripts/setup/bootstrap.sh deploy

# Test targets
test:
	@cd app-src/backend-service && go test -v -race ./...

lint:
	@cd app-src/backend-service && go vet ./...
	@echo "Linting complete"

# Promotion targets
promote-staging:
	@./scripts/deploy/promote.sh dev-to-staging

promote-prod:
	@./scripts/deploy/promote.sh staging-to-prod

status:
	@./scripts/deploy/promote.sh status

# Monitoring targets
health:
	@./scripts/monitoring/health-check.sh all

logs:
	@kubectl logs -n gitops-demo-dev -l app.kubernetes.io/name=backend-service -f

port-forward:
	@echo "Forwarding port 9090 to dev backend-service..."
	@kubectl port-forward svc/dev-backend-service -n gitops-demo-dev 9090:80

port-forward-argocd:
	@echo "Forwarding port 8080 to ArgoCD..."
	@kubectl port-forward svc/argocd-server -n argocd 8080:443

# Context switching
use-dev:
	@kubectl config use-context k3d-gitops-dev

use-staging:
	@kubectl config use-context k3d-gitops-staging

use-prod:
	@kubectl config use-context k3d-gitops-prod

# Validation
validate:
	@echo "Validating Kustomize manifests..."
	@kustomize build gitops-repo/base > /dev/null && echo "✓ Base manifests valid"
	@kustomize build gitops-repo/overlays/dev > /dev/null && echo "✓ Dev overlay valid"
	@kustomize build gitops-repo/overlays/staging > /dev/null && echo "✓ Staging overlay valid"
	@kustomize build gitops-repo/overlays/production > /dev/null && echo "✓ Production overlay valid"

