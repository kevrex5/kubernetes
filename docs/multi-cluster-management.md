# Multi-Cluster Management with ArgoCD

This document describes how to manage multiple Kubernetes clusters from a single ArgoCD instance running in the Management Zone (MZ) cluster.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ArgoCD (MZ Cluster)                                 │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Root Application                                                     │   │
│  │  └── argocd/deployments/                                              │   │
│  │      ├── platform/        → MZ Platform Apps → MZ Cluster             │   │
│  │      ├── workloads/       → MZ Workload Apps → MZ Cluster             │   │
│  │      └── cz/              → CZ Platform Apps → CZ Cluster             │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                │                                           │
                ▼                                           ▼
        ┌───────────────┐                          ┌───────────────┐
        │  MZ Cluster   │                          │  CZ Cluster   │
        │  (in-cluster) │                          │  (external)   │
        │               │                          │               │
        │  • traefik    │                          │  • traefik    │
        │  • cert-mgr   │                          │  • cert-mgr   │
        │  • ext-secrets│                          │  • ext-secrets│
        │  • authentik  │                          │               │
        │  • monitoring │                          │               │
        └───────────────┘                          └───────────────┘
                │                                           │
                ▼                                           ▼
         *.rex5.ca                                  *.cz.cc.rex5.ca
```

## Repository Structure (Multi-Cluster)

```
kubernetes/
├── argocd/
│   ├── deployments/
│   │   ├── platform/           # MZ platform apps (current)
│   │   ├── workloads/          # MZ workload apps
│   │   ├── monitoring/         # MZ monitoring
│   │   └── cz/                 # CZ cluster apps (NEW)
│   │       ├── cz-platform.yaml
│   │       └── cz-security.yaml
│   └── root/
│       └── root.yaml           # Recurses into deployments/
│
├── environments/
│   ├── prod/                   # MZ environment config
│   │   └── config.yaml
│   └── cz/                     # CZ environment config (NEW)
│       └── config.yaml
│
├── platform/                   # MZ platform components
│   ├── namespaces/
│   ├── traefik/
│   ├── cert-manager/
│   └── external-secrets/
│
└── platform-cz/                # CZ platform components (NEW)
    ├── namespaces/
    ├── traefik/
    ├── cert-manager/
    └── external-secrets/
```

## Step 1: Register the CZ Cluster with ArgoCD

ArgoCD needs credentials to manage the external CZ cluster.

### Option A: Using ArgoCD CLI (Recommended for initial setup)

```bash
# 1. Ensure you have contexts for both clusters
kubectl config get-contexts

# 2. Switch to MZ cluster (where ArgoCD runs)
kubectl config use-context <MZ_CONTEXT>

# 3. Login to ArgoCD
argocd login argocd.rex5.ca --grpc-web

# 4. Add the CZ cluster to ArgoCD
# This creates a service account and cluster role in the CZ cluster
argocd cluster add <CZ_CONTEXT> --name cz-cluster

# 5. Verify
argocd cluster list
```

### Option B: Using Declarative Configuration (GitOps)

Create a secret in the ArgoCD namespace:

```bash
# 1. Get the CZ cluster CA certificate and API server URL
kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="<CZ_CONTEXT>")].cluster.certificate-authority-data}' | base64 -d > /tmp/cz-ca.crt
CZ_SERVER=$(kubectl config view -o jsonpath='{.clusters[?(@.name=="<CZ_CONTEXT>")].cluster.server}')

# 2. Create a service account in the CZ cluster for ArgoCD
kubectl --context=<CZ_CONTEXT> create namespace argocd-manager
kubectl --context=<CZ_CONTEXT> create serviceaccount argocd-manager -n argocd-manager
kubectl --context=<CZ_CONTEXT> create clusterrolebinding argocd-manager --clusterrole=cluster-admin --serviceaccount=argocd-manager:argocd-manager

# 3. Get the service account token
# For K8s 1.24+, create a token secret
kubectl --context=<CZ_CONTEXT> apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: argocd-manager
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF

# Wait for token to be generated
sleep 5
CZ_TOKEN=$(kubectl --context=<CZ_CONTEXT> get secret argocd-manager-token -n argocd-manager -o jsonpath='{.data.token}' | base64 -d)

# 4. Store the token in Azure Key Vault
az keyvault secret set --vault-name rex5-cc-mz-prod-kv \
  --name argocd-cz-cluster-token \
  --value "$CZ_TOKEN"

# 5. Create the cluster secret in ArgoCD namespace
# This will be managed by ExternalSecrets for GitOps
```

### Store Cluster Credentials in Key Vault

For a GitOps approach, store cluster credentials in Azure Key Vault:

```bash
# Store CZ cluster details in Key Vault
az keyvault secret set --vault-name rex5-cc-mz-prod-kv \
  --name argocd-cz-cluster-server \
  --value "https://<CZ_API_SERVER>"

az keyvault secret set --vault-name rex5-cc-mz-prod-kv \
  --name argocd-cz-cluster-ca-cert \
  --value "$(cat /tmp/cz-ca.crt | base64 -w0)"

az keyvault secret set --vault-name rex5-cc-mz-prod-kv \
  --name argocd-cz-cluster-token \
  --value "$CZ_TOKEN"
```

Then create an ExternalSecret to sync the cluster credential (see argocd/externalsecret.yaml).

## Step 2: Update Environment Configuration

Edit `environments/cz/config.yaml` with CZ-specific values:

- Azure Key Vault name and URL
- DNS zone for cz.cc.rex5.ca
- Managed Identity client IDs
- Public IP for load balancer
- AKS cluster details

## Step 3: Create CZ Platform Components

The `platform-cz/` directory contains CZ-specific configurations:

```bash
platform-cz/
├── namespaces/
│   ├── kustomization.yaml
│   ├── traefik.yaml
│   ├── cert-manager.yaml
│   └── external-secrets.yaml
├── external-secrets/
│   ├── kustomization.yaml
│   ├── values.yaml              # CZ-specific Helm values
│   └── clustersecretstores.yaml # CZ Key Vault
├── cert-manager/
│   ├── kustomization.yaml
│   ├── values.yaml              # CZ-specific Helm values
│   └── clusterissuers.yaml      # *.cz.cc.rex5.ca issuer
└── traefik/
    ├── kustomization.yaml
    ├── values.yaml              # CZ-specific Helm values
    └── externalsecret.yaml      # Wildcard cert from CZ KV
```

## Step 4: Create ArgoCD Applications for CZ

The `argocd/deployments/cz/` directory defines Applications that target the CZ cluster:

```yaml
# cz-platform.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cz-platform-external-secrets
spec:
  destination:
    server: https://<CZ_API_SERVER>  # Or cluster name after registration
    namespace: rex5-cc-cz-k8s-external-secrets
  # ... rest of application spec
```

## Namespace Naming Convention

To avoid confusion between clusters, use different prefixes:

| Cluster | Namespace Prefix | Example |
|---------|------------------|---------|
| MZ | `rex5-cc-mz-k8s-` | `rex5-cc-mz-k8s-traefik` |
| CZ | `rex5-cc-cz-k8s-` | `rex5-cc-cz-k8s-traefik` |

## Security Considerations

1. **Least Privilege**: Create dedicated managed identities for each cluster
2. **Key Vault Isolation**: Use separate Key Vaults per cluster
3. **Network Security**: Ensure ArgoCD can reach CZ API server (private link or public with NSG)
4. **RBAC**: Use AppProjects to restrict which namespaces each Application can deploy to

## Troubleshooting

### Cluster Connection Issues

```bash
# Check cluster status
argocd cluster list
argocd cluster get cz-cluster

# Test connectivity
kubectl --context=<CZ_CONTEXT> get nodes

# Check ArgoCD logs
kubectl logs -n rex5-cc-mz-k8s-argocd deployment/argocd-application-controller
```

### Sync Issues

```bash
# Check application status
argocd app get cz-platform-traefik
argocd app diff cz-platform-traefik

# Force sync
argocd app sync cz-platform-traefik --force
```
