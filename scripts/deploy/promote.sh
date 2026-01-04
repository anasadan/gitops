#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

get_current_image_tag() {
    local env=$1
    local kustomization="$PROJECT_ROOT/gitops-repo/overlays/$env/kustomization.yaml"
    
    if [[ -f "$kustomization" ]]; then
        grep -A1 "newTag:" "$kustomization" | tail -1 | awk '{print $2}' || echo "latest"
    else
        echo "unknown"
    fi
}

promote() {
    local source_env=$1
    local target_env=$2
    
    log_info "Promoting from $source_env to $target_env..."
    
    local source_kustomization="$PROJECT_ROOT/gitops-repo/overlays/$source_env/kustomization.yaml"
    local target_kustomization="$PROJECT_ROOT/gitops-repo/overlays/$target_env/kustomization.yaml"
    
    if [[ ! -f "$source_kustomization" ]]; then
        log_error "Source kustomization not found: $source_kustomization"
        exit 1
    fi
    
    if [[ ! -f "$target_kustomization" ]]; then
        log_error "Target kustomization not found: $target_kustomization"
        exit 1
    fi
    
    # Get image tag from source
    local image_tag
    image_tag=$(grep "newTag:" "$source_kustomization" | awk '{print $2}')
    
    if [[ -z "$image_tag" ]]; then
        log_error "Could not extract image tag from $source_env"
        exit 1
    fi
    
    log_info "Promoting image tag: $image_tag"
    
    # Update target kustomization
    cd "$PROJECT_ROOT/gitops-repo/overlays/$target_env"
    kustomize edit set image "ghcr.io/anasadan/gitops-demo=ghcr.io/anasadan/gitops-demo:$image_tag"
    
    log_success "Updated $target_env with image tag: $image_tag"
    
    # Show diff
    echo ""
    log_info "Changes made:"
    git diff "$target_kustomization" || true
    
    echo ""
    log_info "To commit these changes:"
    echo "  git add $target_kustomization"
    echo "  git commit -m 'chore: promote $image_tag from $source_env to $target_env'"
    echo "  git push"
}

show_status() {
    echo ""
    log_info "Current image tags by environment:"
    echo ""
    
    for env in dev staging production; do
        local tag
        tag=$(get_current_image_tag "$env")
        printf "  %-12s: %s\n" "$env" "$tag"
    done
    
    echo ""
}

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  dev-to-staging      Promote from dev to staging"
    echo "  staging-to-prod     Promote from staging to production"
    echo "  status              Show current image tags"
    echo ""
    echo "Examples:"
    echo "  $0 dev-to-staging"
    echo "  $0 staging-to-prod"
    echo "  $0 status"
}

main() {
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 1
    fi
    
    local command=$1
    
    case $command in
        dev-to-staging)
            promote "dev" "staging"
            ;;
        staging-to-prod)
            promote "staging" "production"
            ;;
        status)
            show_status
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

