# Vector Charts Deployment Guide

Quick reference for deploying Vector Helm charts to Git and ArgoCD.

## Directory Structure

```
workloads/
├── vector-default/        # Factory-fresh, minimal config
├── vector-azure-simple/   # Single Azure Log Analytics destination
└── vector-claude/         # Dual DCR with hash-based splitting
```

---

## Git Repository Setup

### Initial Setup

```bash
# Navigate to workloads directory
cd /home/krichar/kubernetes/workloads

# Add all Vector charts
git add vector-default/ vector-azure-simple/ vector-claude/

# Commit
git commit -m "feat(vector): add vector helm charts

- vector-default: factory-fresh minimal config
- vector-azure-simple: single Azure Log Analytics destination
- vector-claude: dual DCR with hash-based 50/50 splitting

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

# Push to remote
git push origin master
```

### Updating Charts

```bash
# After making changes
git add workloads/vector-*/
git commit -m "fix(vector): update configuration"
git push origin master
```

---

## ArgoCD Deployment

### Prerequisites

```bash
# Ensure ArgoCD CLI is installed
argocd version

# Login to ArgoCD
argocd login <ARGOCD_SERVER> --username admin --password <PASSWORD>
# Or use SSO:
argocd login <ARGOCD_SERVER> --sso
```

### Option 1: ArgoCD CLI

#### Deploy vector-default

```bash
argocd app create vector-default \
  --repo https://github.com/<org>/<repo>.git \
  --path workloads/vector-default \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace logging \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Sync immediately
argocd app sync vector-default
```

#### Deploy vector-azure-simple

```bash
argocd app create vector-azure-simple \
  --repo https://github.com/<org>/<repo>.git \
  --path workloads/vector-azure-simple \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace logging \
  --values values.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal

argocd app sync vector-azure-simple
```

#### Deploy vector-claude (dual DCR)

```bash
argocd app create vector-syslog \
  --repo https://github.com/<org>/<repo>.git \
  --path workloads/vector-claude \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace logging \
  --values values.yaml \
  --sync-policy automated \
  --auto-prune \
  --self-heal

argocd app sync vector-syslog
```

### Option 2: ArgoCD Application YAML

Create Application manifests in your GitOps repo:

#### vector-default

```yaml
# argocd/applications/vector-default.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vector-default
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/<repo>.git
    targetRevision: HEAD
    path: workloads/vector-default
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: logging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### vector-azure-simple

```yaml
# argocd/applications/vector-azure-simple.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vector-azure-simple
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/<repo>.git
    targetRevision: HEAD
    path: workloads/vector-azure-simple
    helm:
      valueFiles:
        - values.yaml
      # Override values inline
      parameters:
        - name: azure.dcrUri
          value: "https://your-dce.ingest.monitor.azure.com/dataCollectionRules/dcr-xxx/streams/Custom-Logs_CL?api-version=2023-01-01"
  destination:
    server: https://kubernetes.default.svc
    namespace: logging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### vector-claude (dual DCR)

```yaml
# argocd/applications/vector-syslog.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vector-syslog
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/<repo>.git
    targetRevision: HEAD
    path: workloads/vector-claude
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: dcr.dcr1.uri
          value: "https://dce1.ingest.monitor.azure.com/dataCollectionRules/dcr-xxx/streams/Custom-CEF_CL?api-version=2023-01-01"
        - name: dcr.dcr2.uri
          value: "https://dce2.ingest.monitor.azure.com/dataCollectionRules/dcr-yyy/streams/Custom-CEF_CL?api-version=2023-01-01"
  destination:
    server: https://kubernetes.default.svc
    namespace: logging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Apply Application Manifests

```bash
# Apply all ArgoCD applications
kubectl apply -f argocd/applications/

# Or individually
kubectl apply -f argocd/applications/vector-default.yaml
kubectl apply -f argocd/applications/vector-azure-simple.yaml
kubectl apply -f argocd/applications/vector-syslog.yaml
```

---

## Pre-deployment: Create Secrets

Secrets must exist before ArgoCD syncs the applications.

### For vector-azure-simple and vector-claude

```bash
# Create namespace
kubectl create namespace logging

# TLS certificate
kubectl create secret tls vector-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n logging

# Azure token (vector-azure-simple)
kubectl create secret generic azure-log-analytics \
  --from-literal=token='<azure-bearer-token>' \
  -n logging

# Azure token (vector-claude)
kubectl create secret generic azure-ingest-token \
  --from-literal=token='<azure-bearer-token>' \
  -n logging
```

---

## Useful ArgoCD Commands

```bash
# List applications
argocd app list

# Get app status
argocd app get vector-default

# Manual sync
argocd app sync vector-default

# View app diff (what would change)
argocd app diff vector-default

# View app logs
argocd app logs vector-default

# Delete application (keeps resources)
argocd app delete vector-default

# Delete application and resources
argocd app delete vector-default --cascade
```

---

## Helm Direct Deployment (without ArgoCD)

For testing or non-GitOps environments:

```bash
# vector-default
helm install vector-default ./workloads/vector-default -n logging --create-namespace

# vector-azure-simple
helm install vector-azure ./workloads/vector-azure-simple -n logging \
  --set azure.dcrUri="https://..." \
  --create-namespace

# vector-claude
helm install vector-syslog ./workloads/vector-claude -n logging \
  --set dcr.dcr1.uri="https://..." \
  --set dcr.dcr2.uri="https://..." \
  --create-namespace

# Upgrade
helm upgrade vector-default ./workloads/vector-default -n logging

# Uninstall
helm uninstall vector-default -n logging
```
