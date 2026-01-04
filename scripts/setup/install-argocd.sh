#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_VERSION="v2.9.3"
ARGOCD_NAMESPACE="argocd"

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed."
        exit 1
    fi
    
    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    log_success "Prerequisites check passed."
}

install_argocd() {
    log_info "Installing ArgoCD ${ARGOCD_VERSION}..."
    
    # Create namespace
    kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    kubectl apply -n "$ARGOCD_NAMESPACE" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
    
    log_info "Waiting for ArgoCD pods to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE"
    
    log_success "ArgoCD installed successfully!"
}

install_argocd_cli() {
    log_info "Installing ArgoCD CLI..."
    
    if command -v argocd &> /dev/null; then
        log_warn "ArgoCD CLI already installed."
        return
    fi
    
    # Detect OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
    esac
    
    curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-${OS}-${ARCH}"
    chmod +x /tmp/argocd
    sudo mv /tmp/argocd /usr/local/bin/argocd
    
    log_success "ArgoCD CLI installed successfully!"
}

get_admin_password() {
    log_info "Retrieving ArgoCD admin password..."
    
    local password
    password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo ""
    log_success "ArgoCD Admin Credentials:"
    echo "  Username: admin"
    echo "  Password: $password"
    echo ""
}

setup_port_forward() {
    log_info "Setting up port-forward to ArgoCD server..."
    
    echo ""
    echo "Run the following command to access ArgoCD UI:"
    echo ""
    echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo ""
    echo "Then open: https://localhost:8080"
    echo ""
}

apply_custom_configs() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(cd "$script_dir/../.." && pwd)"
    
    log_info "Applying custom ArgoCD configurations..."
    
    # Apply custom ConfigMaps if they exist
    if [[ -f "$project_root/argocd/argocd-cm.yaml" ]]; then
        kubectl apply -f "$project_root/argocd/argocd-cm.yaml"
        log_success "Applied argocd-cm.yaml"
    fi
    
    if [[ -f "$project_root/argocd/argocd-rbac-cm.yaml" ]]; then
        kubectl apply -f "$project_root/argocd/argocd-rbac-cm.yaml"
        log_success "Applied argocd-rbac-cm.yaml"
    fi
    
    # Apply AppProject
    if [[ -f "$project_root/argocd/projects/gitops-demo.yaml" ]]; then
        kubectl apply -f "$project_root/argocd/projects/gitops-demo.yaml"
        log_success "Applied gitops-demo project"
    fi
    
    log_success "Custom configurations applied!"
}

apply_applications() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root
    project_root="$(cd "$script_dir/../.." && pwd)"
    
    log_info "Applying ArgoCD Applications..."
    
    # Apply individual applications
    for app in dev staging production; do
        if [[ -f "$project_root/argocd/applications/${app}.yaml" ]]; then
            kubectl apply -f "$project_root/argocd/applications/${app}.yaml"
            log_success "Applied ${app} application"
        fi
    done
    
    log_success "All applications applied!"
}

show_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  install         Install ArgoCD on current cluster"
    echo "  cli             Install ArgoCD CLI"
    echo "  password        Get admin password"
    echo "  config          Apply custom configurations"
    echo "  apps            Apply ArgoCD Applications"
    echo "  all             Run full installation (install + cli + config + apps)"
    echo ""
    echo "Examples:"
    echo "  $0 install"
    echo "  $0 password"
    echo "  $0 all"
}

main() {
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 1
    fi
    
    local command=$1
    
    case $command in
        install)
            check_prerequisites
            install_argocd
            get_admin_password
            setup_port_forward
            ;;
        cli)
            install_argocd_cli
            ;;
        password)
            get_admin_password
            ;;
        config)
            check_prerequisites
            apply_custom_configs
            ;;
        apps)
            check_prerequisites
            apply_applications
            ;;
        all)
            check_prerequisites
            install_argocd
            install_argocd_cli
            apply_custom_configs
            apply_applications
            get_admin_password
            setup_port_forward
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

