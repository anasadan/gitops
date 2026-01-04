#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

check_cluster() {
    local cluster=$1
    local context="k3d-gitops-$cluster"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Cluster: $cluster"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! kubectl config get-contexts | grep -q "$context"; then
        log_warn "Cluster $cluster not found"
        return
    fi
    
    kubectl config use-context "$context" > /dev/null 2>&1
    
    # Check nodes
    echo ""
    log_info "Nodes:"
    kubectl get nodes -o wide 2>/dev/null || log_error "Failed to get nodes"
    
    # Check system pods
    echo ""
    log_info "System Pods (kube-system):"
    kubectl get pods -n kube-system 2>/dev/null | head -10 || log_error "Failed to get system pods"
}

check_argocd() {
    local context="k3d-gitops-dev"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ArgoCD Status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! kubectl config get-contexts | grep -q "$context"; then
        log_warn "Dev cluster not found"
        return
    fi
    
    kubectl config use-context "$context" > /dev/null 2>&1
    
    # Check ArgoCD pods
    echo ""
    log_info "ArgoCD Pods:"
    kubectl get pods -n argocd 2>/dev/null || log_warn "ArgoCD not installed"
    
    # Check ArgoCD applications
    echo ""
    log_info "ArgoCD Applications:"
    kubectl get applications -n argocd 2>/dev/null || log_warn "No applications found"
}

check_application() {
    local env=$1
    local context="k3d-gitops-$env"
    local namespace="gitops-demo-$env"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Application: $env"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! kubectl config get-contexts | grep -q "$context"; then
        log_warn "Cluster $env not found"
        return
    fi
    
    kubectl config use-context "$context" > /dev/null 2>&1
    
    # Check namespace
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log_warn "Namespace $namespace not found"
        return
    fi
    
    # Check deployments
    echo ""
    log_info "Deployments:"
    kubectl get deployments -n "$namespace" 2>/dev/null || log_warn "No deployments found"
    
    # Check pods
    echo ""
    log_info "Pods:"
    kubectl get pods -n "$namespace" 2>/dev/null || log_warn "No pods found"
    
    # Check services
    echo ""
    log_info "Services:"
    kubectl get svc -n "$namespace" 2>/dev/null || log_warn "No services found"
}

health_check_all() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║     GitOps Infrastructure Health Check   ║"
    echo "╚══════════════════════════════════════════╝"
    
    # Check clusters
    for cluster in dev staging prod; do
        check_cluster "$cluster"
    done
    
    # Check ArgoCD
    check_argocd
    
    # Check applications
    for env in dev staging prod; do
        check_application "$env"
    done
    
    echo ""
    log_success "Health check complete!"
}

show_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  all             Full health check"
    echo "  clusters        Check cluster status"
    echo "  argocd          Check ArgoCD status"
    echo "  apps            Check application status"
    echo ""
}

main() {
    if [[ $# -lt 1 ]]; then
        health_check_all
        exit 0
    fi
    
    local command=$1
    
    case $command in
        all)
            health_check_all
            ;;
        clusters)
            for cluster in dev staging prod; do
                check_cluster "$cluster"
            done
            ;;
        argocd)
            check_argocd
            ;;
        apps)
            for env in dev staging prod; do
                check_application "$env"
            done
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

