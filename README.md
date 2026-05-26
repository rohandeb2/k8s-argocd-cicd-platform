# k8s-argocd-cicd-platform

> A production-grade Kubernetes platform implementing GitOps principles using ArgoCD, GitHub Actions, and Kustomize — featuring multi-environment deployment automation, zero-trust security hardening, autoscaling, and self-healing infrastructure.

![CI/CD](https://img.shields.io/github/actions/workflow/status/rohandeb2/k8s-argocd-cicd-platform/ci-cd.yaml?label=CI%2FCD&style=flat-square)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?style=flat-square&logo=argo&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-multi--arch-2496ED?style=flat-square&logo=docker&logoColor=white)

---

## Overview

This platform automates the full software delivery lifecycle — from code push to production deployment — using GitOps as the core principle. Git is the single source of truth. No one touches the cluster directly.

The platform covers:
- **CI** via GitHub Actions — test, scan, build, push
- **CD** via ArgoCD — Git-driven, self-healing deployments
- **Multi-environment promotion** — dev → staging → prod using Kustomize overlays
- **Security hardening** — zero-trust networking, non-root containers, RBAC, dropped capabilities
- **Autoscaling** — HPA for traffic spikes, VPA for resource optimization
- **High availability** — anti-affinity, topology spread, PodDisruptionBudget

---

## Architecture

![Architecture Diagram](./img/architecture.png)

---

## Tech Stack

| Tool | Role |
|------|------|
| Kubernetes | Container orchestration |
| ArgoCD | GitOps continuous delivery |
| GitHub Actions | CI/CD pipeline automation |
| Kustomize | Multi-environment manifest management |
| Docker | Multi-arch containerization |
| Trivy | Security vulnerability scanning |
| Prometheus | Metrics & observability |
| Redis (StatefulSet) | Stateful workload demonstration |

---

## Repository Structure

```
├──.github/
|    └── workflows/
|        └── ci-cd.yaml            # Full CI/CD pipeline definition
│
├── k8s/
│   ├── base/                     # Environment-agnostic base manifests
│   │   ├── deployment.yaml       # Hardened deployment with probes and lifecycle
│   │   ├── service.yaml          # ClusterIP service
│   │   ├── hpa.yaml              # Horizontal Pod Autoscaler (CPU + memory)
│   │   ├── vpa.yaml              # Vertical Pod Autoscaler (recommendation mode)
│   │   ├── pdb.yaml              # Pod Disruption Budget
│   │   ├── networkpolicy.yaml    # Default-deny + explicit allow rules
│   │   ├── serviceaccount.yaml   # Least-privilege RBAC
│   │   ├── statefulset.yaml      # Redis StatefulSet with per-pod PVCs
│   │   ├── priorityclass.yaml    # High/low priority classes
│   │   ├── namespace.yaml        # Namespace + ResourceQuota + LimitRange
│   │   └── kustomization.yaml
│   │
│   └── overlays/
│       ├── dev/                  # 1 replica · debug logs · automated sync
│       ├── staging/              # 2 replicas · info logs · automated sync
│       └── prod/                 # 3 replicas · warn logs · manual sync
│
├── argocd/
│   ├── root.yaml                 # App of Apps — single bootstrap entry point
│   ├── projects/                 # AppProject — source, destination, RBAC boundaries
│   ├── apps/                     # Per-environment Application manifests
│   └── appsets/                  # ApplicationSet + PreSync/PostSync/SyncFail hooks
|
├── app/                          # Node.js Express application
    ├── src/index.js              # App with health, readiness, metrics endpoints
    ├── Dockerfile                # Multi-stage, non-root, hardened image
    └── package.json
```

---

## CI/CD Pipeline

```
Push to main
      │
      ├── lint-and-test ──────── Node 18 + Node 20 matrix
      │                          npm ci + npm test
      │
      ├── security-scan ──────── Trivy: filesystem scan (source code)
      │                          Trivy: image scan (rohan700/training-app:latest)
      │                          Results uploaded to GitHub Security tab
      │
      └── build-push ─────────── Triggered only on: push to main
            │                    Multi-arch build: linux/amd64 + linux/arm64
            │                    Tags: sha-<commit>, latest, build-<run_number>
            │                    Post-build Trivy scan — blocks on CRITICAL CVEs
            │
            └── update-manifests
                  │              Updates image tag in k8s/overlays/dev + staging
                  │              Commits with [skip ci] to prevent loop
                  │              Pushes to main
                  │
                  └── ArgoCD detects git change → deploys to cluster
```

**Pipeline design decisions:**
- Tests run in parallel on Node 18 and 20 — `fail-fast: true` cancels sibling on first failure
- Security scan runs in parallel with tests — does not block build if low/medium CVEs found
- Build only runs on `push` to `main` — never on pull requests
- Pipeline never applies to cluster directly — only updates Git (GitOps)
- `[skip ci]` on manifest commit prevents infinite pipeline loop

---

## GitOps with ArgoCD

### App of Apps Pattern

One root application manages all environments. Bootstrap once — never touch again.

```
kubectl apply -f argocd/root.yaml
```

```
root-app  (watches argocd/apps/)
    ├── training-app-dev      → k8s/overlays/dev      (automated sync)
    ├── training-app-staging  → k8s/overlays/staging   (automated sync)
    └── training-app-prod     → k8s/overlays/prod      (manual sync — safer for prod)
```

Adding a new environment is as simple as adding a new `application-perf.yaml` to `argocd/apps/` and pushing to Git. ArgoCD creates it automatically.

### Sync Hooks

| Hook | When it runs | What it does |
|------|-------------|--------------|
| PreSync | Before any resource is applied | Runs DB migration job |
| PostSync | After all resources are healthy | Smoke tests `/healthz` and `/readyz` |
| SyncFail | Only when sync fails | Sends alert (Slack/PagerDuty in production) |

If any hook fails → ArgoCD marks the entire sync as Failed. Nothing broken reaches the cluster.

### Self-Healing

If someone manually changes a resource in the cluster, ArgoCD detects the drift and reverts it back to the Git state within seconds.

### AppProject Boundaries

The `devops-training` AppProject enforces:
- Only this repository can be used as source
- Deployments only allowed to `devops-training-dev`, `devops-training-staging`, `devops-training-prod`
- Only whitelisted resource types can be created (Deployment, Service, HPA, etc.)
- `dev-team` can only view and sync dev environment
- `platform-team` has full access to all environments

---

## Kubernetes Platform Features

### Security Hardening

Every workload follows defense-in-depth:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

- **Zero-trust NetworkPolicy** — default-deny-all, explicit allow only for required ports
- **RBAC least privilege** — ServiceAccount can only `get` and `list` ConfigMaps
- **No hardcoded secrets** — injected via Kubernetes Secrets as env vars

### Autoscaling

| Scaler | Trigger | Behavior |
|--------|---------|---------|
| HPA | CPU > 60% or Memory > 70% | Scale up: 2 pods/30s · Scale down: 1 pod/60s (5min stabilization) |
| VPA | Actual vs requested resource usage | Recommendation mode — informs right-sizing without restarts |

VPA and HPA work together: VPA recommends correct resource requests → HPA scales accurately based on real utilization percentages.

### High Availability

- **Pod Anti-Affinity** — pods prefer different nodes (prevents single node failure taking down all replicas)
- **TopologySpreadConstraints** — balances pod count evenly across nodes (`maxSkew: 1`)
- **PodDisruptionBudget** — minimum 1 pod always available during node drains or cluster upgrades
- **Rolling update** — `maxSurge: 1`, `maxUnavailable: 0` — zero downtime deployments
- **Graceful shutdown** — `preStop: sleep 5` + `terminationGracePeriodSeconds: 60`

### Multi-Environment with Kustomize

Base manifests define the full configuration once. Overlays only patch what differs.

| Configuration | dev | staging | prod |
|---------------|-----|---------|------|
| Replicas | 1 | 2 | 3 |
| Log level | debug | info | warn |
| Image pull policy | IfNotPresent | IfNotPresent | Always |
| ArgoCD sync | Automated | Automated | Manual |
| HPA min replicas | 1 | 2 | 2 |

### StatefulSet — Redis

Demonstrates stateful workload management:
- Stable pod names: `training-cache-0`, `training-cache-1`
- Per-pod PVCs: `data-training-cache-0`, `data-training-cache-1`
- Ordered startup (pod-0 ready before pod-1 starts)
- Headless service for stable DNS per pod
- Canary-capable via `partition` field

---

## Deployment Guide

### Prerequisites

```bash
docker --version    # Docker Desktop
kubectl version     # kubectl CLI
minikube version    # Minikube
```

## Application Endpoints

| Endpoint | Probe type | Description |
|----------|-----------|-------------|
| `GET /` | — | App info: version, env, hostname |
| `GET /healthz` | Liveness | Is the process alive? |
| `GET /readyz` | Readiness | Is the app ready to serve traffic? |
| `GET /startupz` | Startup | Has the app finished initializing? |
| `GET /metrics` | — | Prometheus-compatible metrics |

---

## Production Considerations

This platform runs on Minikube for local demonstration. For a production deployment:

| Area | Recommendation |
|------|---------------|
| Cluster | Replace Minikube with EKS / GKE / AKS |
| Secrets | Use AWS Secrets Manager, HashiCorp Vault, or Sealed Secrets |
| VPA | Switch from `Off` to `Auto` mode after establishing resource baselines |
| ArgoCD | Enable SSO (Dex + OIDC) instead of admin password |
| Image registry | Use ECR or GCR instead of DockerHub for private images |
| Monitoring | Add Prometheus + Grafana stack for full observability |
| Ingress | Add NGINX or AWS ALB Ingress Controller with TLS |

---
## Proof of work:
![Proof of Work](./img/Deployed.png)

## Author

**Rohan** — DevOps Engineer  
GitHub: [@rohandeb2](https://github.com/rohandeb2)  
email: ruhondeb28@gmail.com

---
