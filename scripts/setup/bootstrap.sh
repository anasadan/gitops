#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

check_prerequisites() {
    log_step "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    for tool in docker kubectl k3d git; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools:"
        echo "  - docker: https://docs.docker.com/get-docker/"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - k3d: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
        echo "  - git: https://git-scm.com/downloads"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker."
        exit 1
    fi
    
    log_success "All prerequisites are met!"
}

create_clusters() {
    log_step "Creating K3D Clusters"
    
    chmod +x "$SCRIPT_DIR/create-clusters.sh"
    "$SCRIPT_DIR/create-clusters.sh" create-all
}

install_argocd_on_dev() {
    log_step "Installing ArgoCD on Dev Cluster"
    
    # Switch to dev cluster
    kubectl config use-context k3d-gitops-dev
    
    chmod +x "$SCRIPT_DIR/install-argocd.sh"
    "$SCRIPT_DIR/install-argocd.sh" all
}

build_and_push_image() {
    log_step "Building and Pushing Application Image"
    
    local registry="localhost:5050"
    local image_name="gitops-demo"
    local image_tag="latest"
    
    log_info "Building Docker image..."
    docker build \
        -t "$registry/$image_name:$image_tag" \
        -f "$PROJECT_ROOT/app-src/backend-service/Dockerfile" \
        --build-arg VERSION=dev \
        --build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --build-arg GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
        "$PROJECT_ROOT/app-src/backend-service"
    
    log_info "Pushing image to local registry..."
    docker push "$registry/$image_name:$image_tag"
    
    log_success "Image built and pushed: $registry/$image_name:$image_tag"
}

update_local_image_refs() {
    log_step "Updating Image References for Local Development"
    
    local registry="k3d-gitops-registry:5050"
    
    # Update kustomization files to use local registry
    log_info "Updating overlay image references..."
    
    for env in dev staging production; do
        local kustomization="$PROJECT_ROOT/gitops-repo/overlays/$env/kustomization.yaml"
        if [[ -f "$kustomization" ]]; then
            # Use sed to update the image reference
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' "s|ghcr.io/anasadan/gitops-demo|$registry/gitops-demo|g" "$kustomization"
            else
                sed -i "s|ghcr.io/anasadan/gitops-demo|$registry/gitops-demo|g" "$kustomization"
            fi
            log_success "Updated $env overlay"
        fi
    done
}

deploy_to_dev() {
    log_step "Deploying Application to Dev Cluster"
    
    kubectl config use-context k3d-gitops-dev
    
    log_info "Applying Kustomize manifests..."
    kubectl apply -k "$PROJECT_ROOT/gitops-repo/overlays/dev"
    
    log_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/dev-backend-service -n gitops-demo-dev
    
    log_success "Application deployed to dev cluster!"
}

verify_deployment() {
    log_step "Verifying Deployment"
    
    kubectl config use-context k3d-gitops-dev
    
    echo ""
    log_info "Pods in gitops-demo-dev namespace:"
    kubectl get pods -n gitops-demo-dev
    
    echo ""
    log_info "Services in gitops-demo-dev namespace:"
    kubectl get svc -n gitops-demo-dev
    
    echo ""
    log_info "ArgoCD Applications:"
    kubectl get applications -n argocd 2>/dev/null || log_warn "No ArgoCD applications found yet"
}

print_summary() {
    log_step "Bootstrap Complete!"
    
    echo "Your GitOps environment is ready!"
    echo ""
    echo "Clusters created:"
    echo "  - k3d-gitops-dev"
    echo "  - k3d-gitops-staging"
    echo "  - k3d-gitops-prod"
    echo ""
    echo "To access ArgoCD:"
    echo "  1. kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  2. Open https://localhost:8080"
    echo "  3. Login with admin and the password shown above"
    echo ""
    echo "To test the application:"
    echo "  kubectl port-forward svc/dev-backend-service -n gitops-demo-dev 9090:80"
    echo "  curl http://localhost:9090/health"
    echo ""
    echo "To switch between clusters:"
    echo "  kubectl config use-context k3d-gitops-dev"
    echo "  kubectl config use-context k3d-gitops-staging"
    echo "  kubectl config use-context k3d-gitops-prod"
    echo ""
    echo "Next steps:"
    echo "  1. Push this repo to GitHub"
    echo "  2. Update argocd/applications/*.yaml with your repo URL"
    echo "  3. Enable GitHub Actions in your repository settings"
    echo "  4. Create GHCR token for pushing images"
}

cleanup() {
    log_step "Cleaning Up Environment"
    
    chmod +x "$SCRIPT_DIR/create-clusters.sh"
    "$SCRIPT_DIR/create-clusters.sh" delete-all
    
    log_success "Environment cleaned up!"
}

show_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  full          Full bootstrap (clusters + ArgoCD + build + deploy)"
    echo "  clusters      Create K3D clusters only"
    echo "  argocd        Install ArgoCD on dev cluster"
    echo "  build         Build and push application image"
    echo "  deploy        Deploy application to dev"
    echo "  verify        Verify deployment status"
    echo "  cleanup       Delete all clusters and cleanup"
    echo ""
    echo "Examples:"
    echo "  $0 full       # Complete setup"
    echo "  $0 clusters   # Just create clusters"
    echo "  $0 cleanup    # Remove everything"
}

main() {
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 1
    fi
    
    local command=$1
    
    case $command in
        full)
            check_prerequisites
            create_clusters
            install_argocd_on_dev
            build_and_push_image
            update_local_image_refs
            deploy_to_dev
            verify_deployment
            print_summary
            ;;
        clusters)
            check_prerequisites
            create_clusters
            ;;
        argocd)
            check_prerequisites
            install_argocd_on_dev
            ;;
        build)
            check_prerequisites
            build_and_push_image
            ;;
        deploy)
            check_prerequisites
            update_local_image_refs
            deploy_to_dev
            ;;
        verify)
            verify_deployment
            ;;
        cleanup)
            cleanup
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

