# Deployment Guide — k8s ArgoCD CI/CD Platform

> Step-by-step guide to deploy the production-grade Kubernetes GitOps platform locally using Minikube and ArgoCD.

---

## Prerequisites

Make sure these are installed before starting:

```bash
docker --version      # Docker Desktop
kubectl version       # kubectl CLI
minikube version      # Minikube
git --version         # Git
```

---

## Step 0 — Fix Repo Name References (if you renamed your repo)

If you renamed your GitHub repository, update all hardcoded references first:

```bash
grep -rl "k8s-argocd-cicd-platform" . | xargs sed -i 's/k8s-argocd-cicd-platform/YOUR-NEW-REPO-NAME/g'
```

Also update your real identity in `.github/workflows/ci-cd.yaml`:

```yaml
git config user.name  "rohandeb2"
git config user.email "ruhondeb28@gmail.com"
```

Then commit and push:

```bash
git add .
git commit -m "fix: update repo URLs to new name"
git push
```

---

## Step 1 — Add GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | How to get it |
|-------------|--------------|
| `DOCKERHUB_USERNAME` | Your DockerHub username (e.g. `rohan700`) |
| `DOCKERHUB_TOKEN` | DockerHub → Account Settings → Security → New Access Token |
| `GH_PAT` | GitHub → Settings → Developer settings → Tokens (classic) → Generate with `repo` scope |

> **Important:** For `GH_PAT`, use a classic token with the full `repo` scope — not a fine-grained token, as they can cause auth issues with push operations.

---

## Step 2 — Push First Docker Image Manually

The pipeline needs a base image to exist on DockerHub before it can run. Push it manually once:

```bash
cd app
docker login
docker build -t rohan700/training-app:latest .
docker push rohan700/training-app:latest
docker tag rohan700/training-app:latest rohan700/training-app:stable
docker push rohan700/training-app:stable
cd ..
```

---

## Step 3 — Start Minikube

```bash
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=4096 \
  --kubernetes-version=stable \
  --addons=metrics-server \
  --addons=ingress \
  --profile=devops-lab
```

Verify the cluster is healthy:

```bash
kubectl get nodes
# Expected: devops-lab   Ready
```

---

## Step 4 — Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for ArgoCD to be fully ready (~2 minutes):

```bash
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s
```

Get the admin password and **save it**:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

---

## Step 5 — Bootstrap ArgoCD Apps

Apply the AppProject first (defines RBAC boundaries), then the per-environment Application manifests:

```bash
kubectl apply -f argocd/projects/devops-training.yaml
kubectl apply -f argocd/apps/application-dev.yaml
kubectl apply -f argocd/apps/application-staging.yaml
kubectl apply -f argocd/apps/application-prod.yaml
```

Verify ArgoCD can see them:

```bash
kubectl get applications -n argocd
```

---

## Step 6 — Open ArgoCD UI

Port-forward the ArgoCD server:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Open **https://localhost:8080** in your browser → accept the certificate warning → login with:

- **Username:** `admin`
- **Password:** the value from Step 4

You should see 3 apps: `training-app-dev`, `training-app-staging`, `training-app-prod` — all showing **OutOfSync**.

---

## Step 7 — Sync Dev and Staging

**Option A — ArgoCD UI:** Click each app → click **Sync** → click **Synchronize**

**Option B — ArgoCD CLI:**

```bash
# Install ArgoCD CLI
curl -sSL -o argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd

# Login
argocd login localhost:8080 \
  --username admin \
  --insecure \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

# Sync
argocd app sync training-app-dev
argocd app sync training-app-staging
```

Watch pods come up:

```bash
watch kubectl get pods -n devops-training-dev
```

> **Note:** `training-app-prod` uses **manual sync** by design — never auto-deploys to prod.

---

## Step 8 — Verify the App is Running

```bash
kubectl port-forward svc/training-app-svc -n devops-training-dev 3001:80 &
curl http://localhost:3001
```

Expected response:

```json
{
  "message": "Production-grade DevOps Training App",
  "version": "v1.0.0-dev",
  "environment": "dev",
  "hostname": "training-app-xxxx"
}
```

Test all health endpoints:

```bash
curl http://localhost:3001/healthz    # liveness
curl http://localhost:3001/readyz     # readiness
curl http://localhost:3001/startupz   # startup
curl http://localhost:3001/metrics    # prometheus metrics
```

---

## Step 9 — Trigger the Full CI/CD Pipeline

Make any code change and push to `main`:

```bash
# Example: update the app message
sed -i 's/Training App/Training App - v2/' app/src/index.js

git add app/src/index.js
git commit -m "feat: trigger pipeline"
git push
```

Then watch the full GitOps flow:

1. **GitHub Actions tab** — pipeline runs: test → scan → build → push image → update kustomization
2. **Kustomization files** — `k8s/overlays/dev/kustomization.yaml` and `staging` get updated with the new SHA tag and committed back automatically
3. **ArgoCD** — detects the Git change and auto-deploys dev and staging
4. **Cluster** — rolling update happens with zero downtime

```bash
# Watch the rolling update live
watch kubectl get pods -n devops-training-dev
```

---

## Quick Status Commands

```bash
# All pods across environments
kubectl get pods -n devops-training-dev
kubectl get pods -n devops-training-staging
kubectl get pods -n devops-training-prod

# ArgoCD app health
kubectl get applications -n argocd

# App logs
kubectl logs -l app=training-app -n devops-training-dev --tail=20

# HPA status
kubectl get hpa -n devops-training-dev

# Resource usage
kubectl top pods -n devops-training-dev
```

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| `update-manifests` fails with "Repository not found" | `GH_PAT` missing or expired | Regenerate a classic token with `repo` scope and update the secret |
| ArgoCD shows OutOfSync indefinitely | Wrong repo URL in application YAML | Check `repoURL` in `argocd/apps/*.yaml` matches your actual repo name |
| Pods stuck in `ImagePullBackOff` | Image not on DockerHub | Run Step 2 manually to push the base image |
| Pipeline skips `build-push` | Push was not to `main` branch | Ensure you're pushing to `main`, not a feature branch |
| ArgoCD can't connect to repo | Repo is private without credentials | Add repo credentials in ArgoCD UI → Settings → Repositories |

---

## Environment Summary

| Setting | dev | staging | prod |
|---------|-----|---------|------|
| Replicas | 1 | 2 | 3 |
| Log level | debug | info | warn |
| ArgoCD sync | Automated | Automated | **Manual** |
| Namespace | `devops-training-dev` | `devops-training-staging` | `devops-training-prod` |
| Image tag | `sha-<commit>` | `sha-<commit>` | `stable` |