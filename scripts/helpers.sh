#!/usr/bin/env bash
# =============================================================
# Handy helper commands for the training lab
# Usage: source scripts/helpers.sh
# =============================================================

# ── Cluster ──────────────────────────────────────────────────
alias k='kubectl'
alias kns='kubectl config set-context --current --namespace'
alias pods='kubectl get pods -n devops-training -o wide'
alias events='kubectl get events -n devops-training --sort-by=.lastTimestamp'

# ── ArgoCD port-forward ────────────────────────────────────────
argocd-ui() {
  echo "Opening ArgoCD UI at https://localhost:8080"
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &
}

argocd-pass() {
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d
  echo ""
}

# ── App port-forward ──────────────────────────────────────────
app-open() {
  echo "App available at http://localhost:3001"
  kubectl port-forward svc/training-app-svc -n devops-training 3001:80 &
}

# ── Watch pods rolling update ─────────────────────────────────
watch-pods() {
  watch kubectl get pods -n devops-training -o wide
}

# ── Trigger rollout (simulating a deploy) ─────────────────────
rollout-restart() {
  kubectl rollout restart deployment/training-app -n devops-training
  kubectl rollout status deployment/training-app -n devops-training
}

# ── Check HPA ────────────────────────────────────────────────
hpa-status() {
  kubectl get hpa -n devops-training
}

# ── ArgoCD app status ─────────────────────────────────────────
argo-status() {
  kubectl get applications -n argocd
}

echo "✅ Helpers loaded. Commands: argocd-ui, argocd-pass, app-open, watch-pods, rollout-restart, hpa-status, argo-status"
