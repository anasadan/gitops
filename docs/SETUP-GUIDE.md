# GitOps Kubernetes Setup Guide

> Complete documentation of the GitOps infrastructure built with K3D, ArgoCD, and GitHub Actions

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Components Built](#components-built)
- [Docker Images](#docker-images)
- [Deployment Flow](#deployment-flow)
- [Local Setup](#local-setup)
- [CI/CD Pipelines](#cicd-pipelines)
- [ArgoCD Configuration](#argocd-configuration)
- [Troubleshooting](#troubleshooting)
- [Quick Reference](#quick-reference)

---

## Overview

This project demonstrates a production-ready GitOps workflow using:
- **K3D** - Local Kubernetes clusters (Rancher's k3s in Docker)
- **ArgoCD** - GitOps continuous delivery
- **GitHub Actions** - CI/CD pipelines
- **Kustomize** - Kubernetes manifest management
- **GitHub Container Registry (GHCR)** - Docker image storage

### Repository
- **GitHub**: https://github.com/anasadan/gitops
- **Docker Images**: https://github.com/anasadan/gitops/pkgs/container/gitops-demo

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GITOPS WORKFLOW                                    │
└─────────────────────────────────────────────────────────────────────────────┘

Developer                     GitHub                          Kubernetes
─────────                     ──────                          ──────────
    │                            │                                 │
    │  1. Push code              │                                 │
    ├───────────────────────────▶│                                 │
    │                            │                                 │
    │                   2. GitHub Actions                          │
    │                      ┌─────┴─────┐                           │
    │                      │ CI: Test  │                           │
    │                      │ CD: Build │                           │
    │                      └─────┬─────┘                           │
    │                            │                                 │
    │                   3. Push to GHCR                            │
    │                      ┌─────┴─────┐                           │
    │                      │ ghcr.io/  │                           │
    │                      │ anasadan/ │                           │
    │                      │ gitops-   │                           │
    │                      │ demo      │                           │
    │                      └─────┬─────┘                           │
    │                            │                                 │
    │                   4. Update manifests                        │
    │                      (kustomization.yaml)                    │
    │                            │                                 │
    │                            │        5. ArgoCD syncs          │
    │                            ├────────────────────────────────▶│
    │                            │                                 │
    │                            │                    6. App deployed
    │                            │                       to cluster
    │                            │                                 │
```

### Cluster Layout (Current)

```
k3d-dev-cluster (Active - ArgoCD Management)
├── Namespace: argocd
│   └── ArgoCD Server, Repo Server, Redis, etc.
├── Namespace: gitops-demo-dev
│   └── backend-service (1 replica)
├── Namespace: gitops-demo-staging
│   └── backend-service (2 replicas)
└── Namespace: gitops-demo-prod
    └── backend-service (3 replicas) [pending sync]

k3d-staging-cluster (Available for multi-cluster)
k3d-prod-cluster (Available for multi-cluster)
```

---

## Components Built

### 1. Go REST API

**Location**: `app-src/backend-service/`

| File | Purpose |
|------|---------|
| `main.go` | REST API with health, readiness, version endpoints |
| `Dockerfile` | Multi-stage build (final image ~8MB) |
| `go.mod` | Go module definition |
| `.golangci.yml` | Linter configuration |

**API Endpoints**:
```
GET /health     → {"status": "healthy", "timestamp": "..."}
GET /healthz    → Same as /health (Kubernetes convention)
GET /ready      → {"status": "ready", "timestamp": "..."}
GET /readyz     → Same as /ready
GET /version    → {"version": "1.0.1", "build_time": "...", "git_commit": "..."}
GET /api/info   → {"service": "backend-service", "environment": "...", "hostname": "..."}
```

### 2. Kubernetes Manifests (Kustomize)

**Location**: `gitops-repo/`

```
gitops-repo/
├── base/                        # Shared resources
│   ├── deployment.yaml          # Deployment template
│   ├── service.yaml             # ClusterIP service
│   ├── configmap.yaml           # Environment config
│   ├── serviceaccount.yaml      # Pod identity
│   └── kustomization.yaml       # Base kustomization
│
└── overlays/
    ├── dev/                     # Development environment
    │   ├── kustomization.yaml   # 1 replica, debug logs
    │   ├── namespace.yaml
    │   └── patch-deployment.yaml
    │
    ├── staging/                 # Staging environment
    │   ├── kustomization.yaml   # 2 replicas, info logs
    │   ├── namespace.yaml
    │   └── patch-deployment.yaml
    │
    └── production/              # Production environment
        ├── kustomization.yaml   # 3 replicas, warn logs
        ├── namespace.yaml
        ├── patch-deployment.yaml
        └── pdb.yaml             # Pod Disruption Budget
```

**Environment Differences**:

| Setting | Dev | Staging | Production |
|---------|-----|---------|------------|
| Replicas | 1 | 2 | 3 |
| CPU Request | 25m | 50m | 100m |
| Memory Request | 32Mi | 64Mi | 128Mi |
| Log Level | debug | info | warn |
| PDB | No | No | Yes (minAvailable: 1) |

### 3. ArgoCD Configuration

**Location**: `argocd/`

```
argocd/
├── applications/
│   ├── dev.yaml           # ArgoCD Application for dev
│   ├── staging.yaml       # ArgoCD Application for staging
│   ├── production.yaml    # ArgoCD Application for prod
│   └── app-of-apps.yaml   # Meta-application pattern
│
├── projects/
│   └── gitops-demo.yaml   # AppProject with RBAC
│
├── argocd-cm.yaml         # ArgoCD ConfigMap
├── argocd-rbac-cm.yaml    # RBAC policies
└── namespace.yaml         # ArgoCD namespace
```

### 4. GitHub Actions Workflows

**Location**: `.github/workflows/`

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yaml` | PR, Push to main | Lint, test, build, validate manifests, security scan |
| `cd.yaml` | Push to main | Build image, push to GHCR, update dev manifests |
| `release.yaml` | Tag `v*.*.*` | Create release, promote staging, approve prod |

### 5. Automation Scripts

**Location**: `scripts/`

```
scripts/
├── setup/
│   ├── create-clusters.sh    # K3D cluster management
│   ├── install-argocd.sh     # ArgoCD installation
│   └── bootstrap.sh          # Full environment setup
│
├── deploy/
│   └── promote.sh            # Manual promotion helper
│
└── monitoring/
    └── health-check.sh       # Health check script
```

---

## Docker Images

### Registry Location
```
ghcr.io/anasadan/gitops-demo
```

### Available Tags
- `latest` - Most recent build from main
- `v1.0.0` - First release
- `v1.0.1` - Current release with workflow fixes
- `<sha>` - Commit-specific builds

### Pull Command
```bash
docker pull ghcr.io/anasadan/gitops-demo:v1.0.1
```

### View in GitHub
https://github.com/anasadan/gitops/pkgs/container/gitops-demo

---

## Deployment Flow

### Continuous Deployment (Push to main)

```
1. Push code to main branch
         │
         ▼
2. CI workflow runs
   - golangci-lint
   - go test
   - go build
   - docker build (test)
   - kustomize build (validate)
   - trivy scan (security)
         │
         ▼
3. CD workflow runs (if CI passes)
   - docker build (multi-arch)
   - docker push to ghcr.io
   - kustomize edit set image
   - git commit & push manifest
         │
         ▼
4. ArgoCD detects change
   - Compares Git vs Cluster
   - Auto-syncs dev environment
         │
         ▼
5. Pod updated in gitops-demo-dev namespace
```

### Release Deployment (Tag v*.*.*)

```
1. Create and push tag
   git tag -a v1.0.1 -m "Release"
   git push origin v1.0.1
         │
         ▼
2. Release workflow triggers
   - Creates GitHub Release
   - Generates changelog
   - Builds release image
         │
         ▼
3. Promote to Staging (automatic)
   - Updates staging/kustomization.yaml
   - ArgoCD syncs staging
         │
         ▼
4. Promote to Production (manual approval)
   - Waits for approval in GitHub
   - Updates production/kustomization.yaml
   - ArgoCD syncs production
```

---

## Local Setup

### Prerequisites
- Docker Desktop or Rancher Desktop
- kubectl
- k3d
- Git

### Quick Start

```bash
# Clone the repository
git clone https://github.com/anasadan/gitops.git
cd gitops

# Make scripts executable
chmod +x scripts/**/*.sh

# Bootstrap everything
./scripts/setup/bootstrap.sh full
```

### Manual Setup

```bash
# 1. Create K3D clusters
./scripts/setup/create-clusters.sh create-all

# 2. Switch to dev cluster
kubectl config use-context k3d-dev-cluster

# 3. Install ArgoCD
./scripts/setup/install-argocd.sh install

# 4. Apply ArgoCD applications
kubectl apply -f argocd/projects/gitops-demo.yaml
kubectl apply -f argocd/applications/dev.yaml
kubectl apply -f argocd/applications/staging.yaml
kubectl apply -f argocd/applications/production.yaml

# 5. Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## CI/CD Pipelines

### CI Pipeline (ci.yaml)

**Triggers**: Pull requests, pushes to main/develop

**Jobs**:
1. **Lint** - golangci-lint with custom config
2. **Test** - Go tests with race detection and coverage
3. **Build** - Compile Go binary
4. **Docker Build** - Test Docker build (no push)
5. **Validate Manifests** - Kustomize + kubeval
6. **Security Scan** - Trivy vulnerability scanner

### CD Pipeline (cd.yaml)

**Triggers**: Push to main (app-src changes)

**Jobs**:
1. **Build & Push** - Multi-arch Docker image to GHCR
2. **Update Manifests** - Update dev overlay with new tag
3. **Notify** - Success/failure notification

### Release Pipeline (release.yaml)

**Triggers**: Tags matching `v*.*.*`

**Jobs**:
1. **Create Release** - GitHub Release with changelog
2. **Build Release Image** - Tagged Docker image
3. **Promote to Staging** - Auto-update staging manifests
4. **Promote to Production** - Manual approval required

---

## ArgoCD Configuration

### Access ArgoCD UI

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser
open https://localhost:8080

# Credentials
Username: admin
Password: <run command below>
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Application Sync Policies

| Environment | Auto-Sync | Self-Heal | Prune |
|-------------|-----------|-----------|-------|
| Dev | Yes | Yes | Yes |
| Staging | Yes | Yes | Yes |
| Production | No (manual) | Yes | No |

### ArgoCD CLI

```bash
# Install CLI
brew install argocd

# Login
argocd login localhost:8080

# List apps
argocd app list

# Sync app
argocd app sync dev-backend-service

# Get app details
argocd app get dev-backend-service
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n gitops-demo-dev

# Check pod logs
kubectl logs -n gitops-demo-dev -l app.kubernetes.io/name=backend-service

# Describe pod
kubectl describe pod -n gitops-demo-dev -l app.kubernetes.io/name=backend-service
```

### ArgoCD Sync Issues

```bash
# Check application status
kubectl get applications -n argocd

# Force refresh
argocd app refresh dev-backend-service

# Hard refresh (invalidate cache)
argocd app refresh dev-backend-service --hard

# Force sync
argocd app sync dev-backend-service --force
```

### Image Pull Errors

```bash
# Check if image exists
docker pull ghcr.io/anasadan/gitops-demo:latest

# Check image pull secret (if private)
kubectl get secrets -n gitops-demo-dev
```

---

## Quick Reference

### Useful Commands

```bash
# Switch contexts
kubectl config use-context k3d-dev-cluster
kubectl config use-context k3d-staging-cluster
kubectl config use-context k3d-prod-cluster

# View all apps
kubectl get applications -n argocd

# Port forward to app
kubectl port-forward svc/dev-backend-service -n gitops-demo-dev 9090:80

# Test endpoints
curl http://localhost:9090/health
curl http://localhost:9090/version

# Create new release
git tag -a v1.1.0 -m "New release" && git push origin v1.1.0

# View logs
kubectl logs -f -n gitops-demo-dev -l app.kubernetes.io/name=backend-service

# Restart deployment
kubectl rollout restart deployment/dev-backend-service -n gitops-demo-dev
```

### URLs

| Resource | URL |
|----------|-----|
| GitHub Repo | https://github.com/anasadan/gitops |
| Docker Images | https://github.com/anasadan/gitops/pkgs/container/gitops-demo |
| GitHub Actions | https://github.com/anasadan/gitops/actions |
| Releases | https://github.com/anasadan/gitops/releases |

---

## What's Next?

1. **Multi-cluster deployment** - Deploy to separate staging/prod clusters
2. **Monitoring** - Add Prometheus/Grafana
3. **Secrets management** - Sealed Secrets or External Secrets
4. **Progressive delivery** - Argo Rollouts for canary/blue-green
5. **Policy enforcement** - OPA Gatekeeper or Kyverno

---

*Generated on: January 4, 2026*
*Version: 1.0.1*

