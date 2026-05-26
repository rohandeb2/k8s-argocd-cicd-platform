# DevOps Training Lab — Complete Guide
### Kubernetes · ArgoCD · GitHub Actions | Zero Cost Local → Cloud

---

## 🗺️ What You Are Building

```
Your Code (GitHub)
      │
      │  git push
      ▼
GitHub Actions CI/CD
  ├── Run tests
  ├── Build Docker image → push to Docker Hub
  └── Update image tag in k8s/overlays/dev & staging
              │
              │  Git commit detected
              ▼
         ArgoCD (GitOps)
    ┌─────────┼──────────┐
    ▼         ▼          ▼
  dev      staging     prod
(auto)     (auto)    (manual approval)
    └─────────┼──────────┘
              ▼
     Kubernetes Cluster (Minikube locally)
```

**One push to main → your app is live on dev+staging automatically. Prod needs your click.**

---

## 📦 Prerequisites — Install These First

| Tool | Purpose | Install |
|------|---------|---------|
| Docker Desktop | Run containers | https://docker.com/products/docker-desktop |
| minikube | Local K8s cluster | `brew install minikube` (Mac) or https://minikube.sigs.k8s.io |
| kubectl | Talk to K8s | `brew install kubectl` |
| git | Version control | Already installed usually |
| VS Code | Code editor | https://code.visualstudio.com |

**Free accounts needed:**
- GitHub account (free)
- Docker Hub account (free) — for storing your images

---

## 📁 Project Structure Explained

```
devops-training-lab/
├── app/                          ← Your Node.js application
│   ├── src/index.js              ← App code
│   ├── package.json
│   └── Dockerfile                ← Multi-stage, non-root, production-grade
│
├── k8s/                          ← All Kubernetes manifests
│   ├── base/                     ← Shared config (DRY principle)
│   │   ├── deployment.yaml       ← Production-grade: probes, limits, security
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── hpa.yaml              ← Auto-scales 2→5 pods on CPU/memory
│   │   ├── pdb.yaml              ← Never kills last pod during updates
│   │   └── kustomization.yaml
│   └── overlays/
│       ├── dev/                  ← Dev-specific overrides (1 replica)
│       ├── staging/              ← Staging overrides (2 replicas)
│       └── prod/                 ← Prod overrides (3 replicas, manual sync)
│
├── argocd/
│   ├── projects/devops-training.yaml              ← RBAC: who can deploy where
│   ├── application-dev.yaml      ← ArgoCD watches k8s/overlays/dev
│   ├── application-staging.yaml
│   └── application-prod.yaml     ← Manual sync only!
│
├── .github/workflows/
│   └── ci-cd.yaml                ← Full CI/CD pipeline
│
└── scripts/
    ├── setup.sh                  ← One-time cluster bootstrap
    └── helpers.sh                ← Useful shortcuts
```

---

## 🚀 DAY 1 — Setup (Do This Once)

### Step 1 — Unzip and go to the project

```bash
unzip devops-training-lab.zip
cd devops-training-lab
```

### Step 2 — Create your GitHub repository

1. Go to https://github.com/new
2. Name it: `devops-training-lab`
3. Set to **Public** (ArgoCD will pull from it)
4. Do NOT add README (you already have files)

```bash
# Initialize git and push
git init
git add .
git commit -m "feat: initial devops training lab setup"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/devops-training-lab.git
git push -u origin main
```

### Step 3 — Update YOUR username in config files

Search and replace `YOUR_USERNAME` and `your-dockerhub-username` in these files:

```bash
# On Mac/Linux:
grep -r "YOUR_USERNAME\|your-dockerhub-username" . --include="*.yaml" --include="*.yml"
```

Files to update:
- `k8s/overlays/dev/kustomization.yaml` → your Docker Hub username
- `k8s/overlays/staging/kustomization.yaml` → same
- `k8s/overlays/prod/kustomization.yaml` → same
- `argocd/projects/devops-training.yaml` → your GitHub username
- `argocd/application-dev.yaml` → your GitHub username
- `argocd/application-staging.yaml` → same
- `argocd/application-prod.yaml` → same

Then push the changes:
```bash
git add .
git commit -m "chore: set my username in configs"
git push
```

### Step 4 — Run the setup script

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

This will:
- Start a Minikube cluster
- Install ArgoCD
- Print your ArgoCD password

**Save the password it prints!**

### Step 5 — Verify cluster is running

```bash
kubectl get nodes
# Should show: minikube   Ready   ...

kubectl get pods -n argocd
# Should show argocd-server, argocd-repo-server, etc. all Running
```

### Step 6 — Open ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open your browser: **https://localhost:8080**
- Username: `admin`
- Password: (from setup script output)

Accept the self-signed certificate warning.

### Step 7 — Apply ArgoCD Project and Applications

```bash
# Create the ArgoCD project (RBAC rules)
kubectl apply -f argocd/projects/devops-training.yaml

# Create the three applications (dev, staging, prod)
kubectl apply -f argocd/application-dev.yaml
kubectl apply -f argocd/application-staging.yaml
kubectl apply -f argocd/application-prod.yaml
```

Go to ArgoCD UI → you will see 3 apps. They will show "OutOfSync" initially.

### Step 8 — Set up GitHub Actions Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions → New repository secret

| Secret Name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not password) |
| `GH_PAT` | GitHub Personal Access Token |

**How to get Docker Hub token:**
1. hub.docker.com → Account Settings → Security → New Access Token
2. Name: `github-actions`, Permission: Read/Write

**How to get GitHub PAT:**
1. github.com → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Select your repo → Permissions: Contents (Read and Write), Workflows (Read and Write)

---

## 🔄 DAY 2 — Your First Deployment

### Step 9 — Build and push your first Docker image manually

```bash
cd app

# Log in to Docker Hub
docker login

# Build the image
docker build -t YOUR_DOCKERHUB_USERNAME/training-app:v1.0.0 .

# Push it
docker push YOUR_DOCKERHUB_USERNAME/training-app:v1.0.0

# Also tag as latest
docker tag YOUR_DOCKERHUB_USERNAME/training-app:v1.0.0 \
           YOUR_DOCKERHUB_USERNAME/training-app:latest
docker push YOUR_DOCKERHUB_USERNAME/training-app:latest

cd ..
```

### Step 10 — Sync ArgoCD manually (first time)

In the ArgoCD UI:
1. Click on `training-app-dev`
2. Click **SYNC** → **SYNCHRONIZE**
3. Watch pods appear!

Or from the terminal:
```bash
# Install ArgoCD CLI
brew install argocd   # Mac
# Or: https://argo-cd.readthedocs.io/en/stable/cli_installation/

# Login
argocd login localhost:8080 --username admin --password YOUR_PASSWORD --insecure

# Sync dev app
argocd app sync training-app-dev
```

### Step 11 — Verify your app is running

```bash
kubectl get pods -n devops-training
# NAME                            READY   STATUS    RESTARTS   AGE
# training-app-xxxxx-yyy          1/1     Running   0          30s

# Access the app
kubectl port-forward svc/training-app-svc -n devops-training 3001:80
```

Open: **http://localhost:3001**
You should see:
```json
{
  "message": "Hello from DevOps Training App!",
  "version": "v1.0.0-dev",
  "environment": "dev",
  "hostname": "training-app-xxxxx"
}
```

**🎉 Your app is running on Kubernetes!**

---

## ⚙️ DAY 3 — GitOps in Action (The Magic)

### Make a code change and watch everything flow automatically

```bash
# Edit the app message
# Open app/src/index.js and change "Hello from DevOps Training App!"
# to "Hello from DevOps Training App! - Updated v2!"
```

Push the change:
```bash
git add .
git commit -m "feat: update welcome message"
git push
```

Now watch what happens automatically:

1. **GitHub Actions triggers** → go to github.com/YOUR_USERNAME/devops-training-lab → Actions tab
2. **Test job** runs
3. **Build job** builds Docker image, pushes to Docker Hub
4. **Update manifest job** edits `k8s/overlays/dev/kustomization.yaml` with the new image tag and commits it
5. **ArgoCD detects** the git change (polls every 3 minutes by default)
6. **ArgoCD syncs** the new image to your cluster
7. **Rolling update** — old pods replaced one by one, zero downtime

**This is GitOps — Git is the single source of truth!**

### Watch the rolling update live:

```bash
watch kubectl get pods -n devops-training
```

You'll see new pods come up before old ones terminate. That's `maxUnavailable: 0` in action.

---

## 🔬 DAY 4 — Kubernetes Deep Dive

### Concept 1: Probes (how K8s knows your app is alive)

```bash
# See probe configuration
kubectl describe deployment training-app -n devops-training | grep -A 20 "Liveness\|Readiness"

# Kill the health endpoint (simulate app crash) — watch K8s restart it
kubectl exec -it $(kubectl get pod -n devops-training -l app=training-app -o name | head -1) \
  -n devops-training -- kill 1
  
# Watch it restart automatically
kubectl get pods -n devops-training -w
```

### Concept 2: Resource limits

```bash
# See resource usage per pod
kubectl top pods -n devops-training

# See limits configured
kubectl describe pod -n devops-training -l app=training-app | grep -A 5 "Limits\|Requests"
```

### Concept 3: HPA (Auto-scaling)

```bash
# Check HPA status
kubectl get hpa -n devops-training

# Watch it scale (you'd need to add load for this to trigger)
kubectl describe hpa training-app-hpa -n devops-training
```

### Concept 4: PodDisruptionBudget

```bash
# Check PDB — ensures at least 1 pod is always alive
kubectl get pdb -n devops-training
kubectl describe pdb training-app-pdb -n devops-training
```

### Concept 5: Drift detection (ArgoCD self-heal)

```bash
# Manually scale to 5 replicas (not in Git!)
kubectl scale deployment training-app -n devops-training --replicas=5

# Watch pods go to 5
kubectl get pods -n devops-training

# Wait ~3 minutes... ArgoCD will detect the drift and scale back to what Git says
kubectl get pods -n devops-training -w
# Observe: it goes back to the replica count in your kustomization overlay
```

**This is why self-healing is critical in production — no one can manually change production state without going through Git.**

---

## 🛡️ DAY 5 — ArgoCD Advanced Concepts

### Manual Production Deploy (with approval)

Dev and staging sync automatically. Production requires human approval.

```bash
# Check prod app status
argocd app get training-app-prod

# When you're ready to promote to prod, update prod overlay to use same tag
# Edit k8s/overlays/prod/kustomization.yaml → change newTag to the sha you want
# Commit and push

# Then in ArgoCD UI, click training-app-prod → SYNC
# Or via CLI:
argocd app sync training-app-prod
```

### Rollback in ArgoCD

```bash
# See deployment history
argocd app history training-app-dev

# Roll back to previous version
argocd app rollback training-app-dev 1
# (1 is the revision number from history)
```

### Watch sync status

```bash
# Check all apps at once
kubectl get applications -n argocd

# Detailed status of one app
argocd app get training-app-dev
```

---

## 🐛 Troubleshooting

### ArgoCD shows OutOfSync

```bash
argocd app sync training-app-dev --force
```

### Pod stuck in Pending

```bash
kubectl describe pod POD_NAME -n devops-training
# Look at "Events" section at the bottom — it tells you why
```

### Image pull error

```bash
# Check if Docker Hub image exists
docker pull YOUR_DOCKERHUB_USERNAME/training-app:latest

# Make sure the image name in kustomization.yaml exactly matches
```

### ArgoCD can't reach GitHub

```bash
# Add your repo manually in ArgoCD
argocd repo add https://github.com/YOUR_USERNAME/devops-training-lab.git \
  --username YOUR_USERNAME \
  --password YOUR_GITHUB_PAT
```

### Minikube out of memory

```bash
minikube stop
minikube start --driver=docker --cpus=4 --memory=6144 --profile=devops-lab
```

---

## 🚀 Moving to the Cloud (Next Phase)

When you're ready to move from local to cloud (zero cost options):

| Option | Cost | Notes |
|--------|------|-------|
| GKE Autopilot | Free tier | $0 for small clusters |
| k3s on a free VPS (Oracle Cloud free tier) | Free | Oracle gives 2 ARM VMs free forever |
| EKS via AWS free tier | Limited | Only 750hrs t3.micro |
| Civo (managed K3s) | $5/mo | Cheapest managed K8s |

**Everything in this lab works identically on cloud — just change the kubeconfig.**

---

## 📚 Production Concepts You've Practiced

| Concept | Where |
|---------|-------|
| Multi-stage Docker build | `app/Dockerfile` |
| Non-root container user | `app/Dockerfile` |
| ReadOnlyRootFilesystem | `k8s/base/deployment.yaml` |
| Liveness + Readiness probes | `k8s/base/deployment.yaml` |
| CPU + Memory resource limits | `k8s/base/deployment.yaml` |
| Pod Anti-Affinity (spread across nodes) | `k8s/base/deployment.yaml` |
| Rolling update with zero downtime | `k8s/base/deployment.yaml` |
| HPA (auto-scale on CPU/memory) | `k8s/base/hpa.yaml` |
| PodDisruptionBudget | `k8s/base/pdb.yaml` |
| Kustomize overlays (DRY config) | `k8s/overlays/` |
| GitOps with ArgoCD | `argocd/` |
| Drift detection + self-healing | ArgoCD automated syncPolicy |
| Manual prod approval gate | `argocd/application-prod.yaml` |
| RBAC via ArgoCD Projects | `argocd/projects/devops-training.yaml` |
| CI pipeline with test → build → push | `.github/workflows/ci-cd.yaml` |
| Image tag update via kustomize in CI | `.github/workflows/ci-cd.yaml` |
| Pipeline concurrency control | `.github/workflows/ci-cd.yaml` |
| Docker layer caching in CI | `.github/workflows/ci-cd.yaml` |
| GitHub Actions job dependencies | `.github/workflows/ci-cd.yaml` |

---

## 💡 Daily Practice Commands (Bookmark These)

```bash
# Source helpers for shortcuts
source scripts/helpers.sh

# Open ArgoCD UI
argocd-ui

# Get ArgoCD password
argocd-pass

# Open your app in browser
app-open

# Watch pods live
watch-pods

# Check all ArgoCD apps
argo-status

# Simulate a deploy restart
rollout-restart
```
