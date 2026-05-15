#!/usr/bin/env bash
# =============================================================
# DevOps Training Lab — Local Setup Script
# Run this ONCE on Day 1 to set up your entire local cluster
# =============================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${BLUE}[→]${NC} $1"; }
die()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "================================================="
echo "   DevOps Training Lab — Environment Bootstrap"
echo "================================================="
echo ""

# ── Step 1: Check prerequisites ──────────────────────────────
info "Checking prerequisites..."

command -v docker   &>/dev/null || die "Docker not found. Install Docker Desktop first."
command -v kubectl  &>/dev/null || die "kubectl not found. Install kubectl first."
command -v minikube &>/dev/null || die "minikube not found. Install minikube first."
command -v git      &>/dev/null || die "git not found."

log "All prerequisites found."

# ── Step 2: Start Minikube ────────────────────────────────────
info "Starting Minikube cluster (4 CPU, 4GB RAM)..."

minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=4096 \
  --kubernetes-version=stable \
  --addons=metrics-server \
  --addons=ingress \
  --profile=devops-lab

log "Minikube started."

# ── Step 3: Verify cluster ────────────────────────────────────
info "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s
log "Cluster is ready."

# ── Step 4: Install ArgoCD ────────────────────────────────────
info "Installing ArgoCD..."

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for ArgoCD pods to be ready (this takes ~2 minutes)..."
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s

log "ArgoCD installed."

# ── Step 5: Get ArgoCD initial password ──────────────────────
info "Retrieving ArgoCD admin password..."
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# ── Step 6: Create devops-training namespace ──────────────────
info "Creating devops-training namespace..."
kubectl create namespace devops-training --dry-run=client -o yaml | kubectl apply -f -
log "Namespace created."

# ── Step 7: Port-forward ArgoCD (background) ─────────────────
info "Starting ArgoCD port-forward on localhost:8080..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &>/dev/null &
PF_PID=$!
echo $PF_PID > /tmp/argocd-pf.pid
sleep 2

# ── Done ─────────────────────────────────────────────────────
echo ""
echo "================================================="
echo -e "  ${GREEN}Setup Complete!${NC}"
echo "================================================="
echo ""
echo -e "  ${BLUE}ArgoCD UI:${NC}       https://localhost:8080"
echo -e "  ${BLUE}Username:${NC}         admin"
echo -e "  ${BLUE}Password:${NC}         ${ARGOCD_PASS}"
echo ""
echo "  Save this password! Or run:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo -e "  ${YELLOW}Next step:${NC} Follow the TRAINING-GUIDE.md"
echo ""
