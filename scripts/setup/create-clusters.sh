#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_PREFIX="gitops"
K3D_VERSION="v5.6.0"
REGISTRY_NAME="gitops-registry"
REGISTRY_PORT="5050"

# Cluster configurations
declare -A CLUSTER_CONFIG=(
    ["dev"]="--servers 1 --agents 1"
    ["staging"]="--servers 1 --agents 2"
    ["prod"]="--servers 1 --agents 3"
)

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
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check for k3d
    if ! command -v k3d &> /dev/null; then
        log_warn "k3d is not installed. Installing..."
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    fi
    
    # Check for kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    log_success "All prerequisites are met."
}

create_registry() {
    log_info "Creating local container registry..."
    
    if k3d registry list | grep -q "$REGISTRY_NAME"; then
        log_warn "Registry $REGISTRY_NAME already exists. Skipping..."
    else
        k3d registry create "$REGISTRY_NAME" --port "$REGISTRY_PORT"
        log_success "Registry created at localhost:$REGISTRY_PORT"
    fi
}

create_cluster() {
    local env=$1
    local cluster_name="${CLUSTER_PREFIX}-${env}"
    local config="${CLUSTER_CONFIG[$env]}"
    
    log_info "Creating cluster: $cluster_name"
    
    if k3d cluster list | grep -q "$cluster_name"; then
        log_warn "Cluster $cluster_name already exists. Skipping..."
        return
    fi
    
    k3d cluster create "$cluster_name" \
        $config \
        --registry-use "k3d-${REGISTRY_NAME}:${REGISTRY_PORT}" \
        --k3s-arg "--disable=traefik@server:0" \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --wait
    
    # Label the cluster for ArgoCD targeting
    kubectl config use-context "k3d-${cluster_name}"
    kubectl label node "k3d-${cluster_name}-server-0" env="$env" --overwrite
    
    log_success "Cluster $cluster_name created successfully!"
}

create_all_clusters() {
    log_info "Creating all clusters..."
    
    for env in "${!CLUSTER_CONFIG[@]}"; do
        create_cluster "$env"
    done
    
    log_success "All clusters created!"
}

list_clusters() {
    log_info "Listing all k3d clusters..."
    k3d cluster list
}

delete_cluster() {
    local env=$1
    local cluster_name="${CLUSTER_PREFIX}-${env}"
    
    log_info "Deleting cluster: $cluster_name"
    
    if k3d cluster list | grep -q "$cluster_name"; then
        k3d cluster delete "$cluster_name"
        log_success "Cluster $cluster_name deleted."
    else
        log_warn "Cluster $cluster_name does not exist."
    fi
}

delete_all_clusters() {
    log_info "Deleting all clusters..."
    
    for env in "${!CLUSTER_CONFIG[@]}"; do
        delete_cluster "$env"
    done
    
    # Delete registry
    if k3d registry list | grep -q "$REGISTRY_NAME"; then
        k3d registry delete "$REGISTRY_NAME"
        log_success "Registry deleted."
    fi
    
    log_success "All clusters deleted!"
}

switch_context() {
    local env=$1
    local cluster_name="${CLUSTER_PREFIX}-${env}"
    
    if kubectl config get-contexts | grep -q "k3d-${cluster_name}"; then
        kubectl config use-context "k3d-${cluster_name}"
        log_success "Switched to context: k3d-${cluster_name}"
    else
        log_error "Context k3d-${cluster_name} does not exist."
        exit 1
    fi
}

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create-all          Create all clusters (dev, staging, prod)"
    echo "  create <env>        Create a specific cluster (dev|staging|prod)"
    echo "  delete-all          Delete all clusters"
    echo "  delete <env>        Delete a specific cluster"
    echo "  list                List all clusters"
    echo "  switch <env>        Switch kubectl context to a cluster"
    echo "  registry            Create local container registry"
    echo ""
    echo "Examples:"
    echo "  $0 create-all"
    echo "  $0 create dev"
    echo "  $0 switch staging"
    echo "  $0 delete prod"
}

# Main
main() {
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 1
    fi
    
    local command=$1
    
    case $command in
        create-all)
            check_prerequisites
            create_registry
            create_all_clusters
            ;;
        create)
            if [[ $# -lt 2 ]]; then
                log_error "Please specify environment: dev, staging, or prod"
                exit 1
            fi
            check_prerequisites
            create_registry
            create_cluster "$2"
            ;;
        delete-all)
            delete_all_clusters
            ;;
        delete)
            if [[ $# -lt 2 ]]; then
                log_error "Please specify environment: dev, staging, or prod"
                exit 1
            fi
            delete_cluster "$2"
            ;;
        list)
            list_clusters
            ;;
        switch)
            if [[ $# -lt 2 ]]; then
                log_error "Please specify environment: dev, staging, or prod"
                exit 1
            fi
            switch_context "$2"
            ;;
        registry)
            check_prerequisites
            create_registry
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

