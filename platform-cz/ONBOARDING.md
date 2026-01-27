# CZ Platform Region Onboarding Guide

This document describes how to onboard a new Azure region to the Customer Zone (CZ) platform infrastructure.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Terraform/Terragrunt (Infrastructure)                    │
│                                                                              │
│  Creates per-region:                                                         │
│  • AKS Cluster (private)           • VNet + Peering to MZ                   │
│  • Key Vault                        • Private DNS Zone linking               │
│  • Managed Identities               • ArgoCD cluster secret (in MZ)          │
│  • Public IP                        • Federated credentials                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Git Repository (GitOps)                             │
│                                                                              │
│  platform-cz/                                                                │
│  ├── canadacentral/        # Region-specific Kubernetes configs             │
│  ├── eastus/               # (values.yaml, ClusterIssuers, etc.)            │
│  └── westeurope/                                                            │
│                                                                              │
│  argocd/deployments/cz/                                                      │
│  ├── cz-security.yaml      # AppProject (destinations per region)           │
│  └── cz-platform.yaml      # Applications (one set per region)              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What Terraform Manages

| Resource | Created By | Notes |
|----------|------------|-------|
| AKS Cluster | Terraform | Private cluster with OIDC issuer |
| Key Vault | Terraform | With required secrets |
| Managed Identities | Terraform | cert-manager, external-secrets, ArgoCD |
| Federated Credentials | Terraform | OIDC trust for Workload Identity |
| VNet Peering | Terraform | MZ ↔ CZ connectivity |
| Private DNS Zone Link | Terraform | MZ can resolve CZ private FQDN |
| **ArgoCD Cluster Secret** | Terraform | Deployed to MZ cluster |
| Public IP | Terraform | For Traefik LoadBalancer |

### What GitOps Manages

| Resource | Managed In | Notes |
|----------|------------|-------|
| Platform configs | `platform-cz/<region>/` | Helm values, ClusterIssuers, etc. |
| ArgoCD AppProject | `argocd/deployments/cz/cz-security.yaml` | Destinations per region |
| ArgoCD Applications | `argocd/deployments/cz/cz-platform.yaml` | One set per region |

---

## Directory Structure

```
platform-cz/
├── ONBOARDING.md           # This document
├── canadacentral/          # First region (reference implementation)
│   ├── namespaces/
│   ├── cert-manager/
│   ├── external-secrets/
│   ├── hubble/
│   └── traefik/
├── eastus/                  # Example: New region
│   └── ...
└── westeurope/              # Example: Another region
    └── ...
```

---

## Onboarding Steps

### Step 1: Deploy Infrastructure with Terraform

Run Terraform/Terragrunt to create the new region's infrastructure:

```bash
cd terraform/environments/cz/<new-region>
terragrunt apply
```

This creates:
- AKS cluster with private API server
- Key Vault with required secrets
- Managed identities with federated credentials
- VNet peering to MZ
- Private DNS zone linking (so MZ can resolve CZ private FQDN)
- **ArgoCD cluster secret** in MZ cluster (automatically)

**Verify Terraform outputs:**
```bash
terragrunt output

# Expected outputs:
# aks_cluster_name = "rex5-cc-cz-prod-<region>-aks"
# aks_private_fqdn = "rex5-cc-cz-prod-<region>.rex5-cc-cz-prod-<region>-aks.privatelink.<region>.azmk8s.io"
# cert_manager_identity_client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# eso_identity_client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# argocd_identity_client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# keyvault_url = "https://rex5-cc-cz-prod-<region>-kv.vault.azure.net/"
```

**Verify cluster secret was created in MZ:**
```bash
kubectl get secret -n rex5-cc-mz-k8s-argocd -l argocd.argoproj.io/secret-type=cluster
```

---

### Step 2: Create Region Directory Structure

Copy the reference region:

```bash
cp -r platform-cz/canadacentral platform-cz/<new-region>
```

---

### Step 3: Update Platform Configurations

Use the Terraform outputs to update the region configs:

#### 3.1 cert-manager (`platform-cz/<new-region>/cert-manager/values.yaml`)

```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "<TERRAFORM_OUTPUT: cert_manager_identity_client_id>"
```

#### 3.2 cert-manager ClusterIssuers (`platform-cz/<new-region>/cert-manager/clusterissuers.yaml`)

```yaml
spec:
  acme:
    solvers:
      - dns01:
          azureDNS:
            hostedZoneName: "<new-region>.cz.cc.rex5.ca"
            resourceGroupName: "<TERRAFORM_OUTPUT: dns_zone_resource_group>"
            subscriptionID: "<CZ_SUBSCRIPTION_ID>"
```

#### 3.3 external-secrets (`platform-cz/<new-region>/external-secrets/values.yaml`)

```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "<TERRAFORM_OUTPUT: eso_identity_client_id>"
```

#### 3.4 external-secrets ClusterSecretStore (`platform-cz/<new-region>/external-secrets/clustersecretstores.yaml`)

```yaml
spec:
  provider:
    azurekv:
      vaultUrl: "<TERRAFORM_OUTPUT: keyvault_url>"
```

#### 3.5 Traefik (`platform-cz/<new-region>/traefik/values.yaml`)

```yaml
service:
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "<TERRAFORM_OUTPUT: publicip_resource_group>"
  spec:
    loadBalancerIP: "<TERRAFORM_OUTPUT: publicip_address>"
```

---

### Step 4: Update ArgoCD AppProject

Edit `argocd/deployments/cz/cz-security.yaml` to add the new cluster destinations:

```yaml
destinations:
  # Existing canadacentral destinations...
  
  # New region destinations (use Terraform output: aks_private_fqdn)
  - namespace: default
    server: 'https://<TERRAFORM_OUTPUT: aks_private_fqdn>:443'
  - namespace: kube-system
    server: 'https://<TERRAFORM_OUTPUT: aks_private_fqdn>:443'
  - namespace: rex5-cc-cz-k8s-traefik
    server: 'https://<TERRAFORM_OUTPUT: aks_private_fqdn>:443'
  - namespace: rex5-cc-cz-k8s-cert-manager
    server: 'https://<TERRAFORM_OUTPUT: aks_private_fqdn>:443'
  - namespace: rex5-cc-cz-k8s-external-secrets
    server: 'https://<TERRAFORM_OUTPUT: aks_private_fqdn>:443'
```

---

### Step 5: Create ArgoCD Applications

Create `argocd/deployments/cz/cz-platform-<region>.yaml` with Applications for:

| Application | Sync Wave | Path |
|-------------|-----------|------|
| `cz-<region>-namespaces` | -1 | `platform-cz/<region>/namespaces` |
| `cz-<region>-hubble` | 0 | `platform-cz/<region>/hubble` |
| `cz-<region>-cert-manager` | 1 | `platform-cz/<region>/cert-manager` |
| `cz-<region>-external-secrets` | 2 | `platform-cz/<region>/external-secrets` |
| `cz-<region>-traefik` | 3 | `platform-cz/<region>/traefik` |

Each Application should:
- Target the new cluster server URL (from Terraform output)
- Use the `platform-cz` AppProject
- Reference `platform-cz/<region>/` paths

**Template (copy from `cz-platform.yaml` and modify):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cz-<region>-namespaces
  namespace: rex5-cc-mz-k8s-argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: platform-cz
  source:
    repoURL: git@github.com:kevrex5/kubernetes.git
    targetRevision: HEAD
    path: platform-cz/<region>/namespaces
  destination:
    server: 'https://<TERRAFORM_OUTPUT: aks_private_fqdn>:443'
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

### Step 6: Commit and Deploy

```bash
# Create branch
git checkout -b platform-cz/onboard-<region>

# Add files
git add platform-cz/<region>/
git add argocd/deployments/cz/

# Commit
git commit -m "platform-cz(<region>): onboard new region"

# Push
git push origin platform-cz/onboard-<region>

# Merge PR, then ArgoCD auto-syncs
```

---

### Step 7: Verify Deployment

```bash
# Check cluster is registered (Terraform created this)
kubectl get secret -n rex5-cc-mz-k8s-argocd -l argocd.argoproj.io/secret-type=cluster

# Check ArgoCD can reach the cluster
kubectl logs -n rex5-cc-mz-k8s-argocd -l app.kubernetes.io/name=argocd-application-controller | grep <region>

# Check applications are syncing
argocd app list | grep cz-<region>
```

---

## Checklist

### Terraform (Infrastructure)
- [ ] AKS cluster created and healthy
- [ ] Key Vault created with required secrets  
- [ ] Managed identities created with correct role assignments
- [ ] Federated credentials configured for all identities
- [ ] VNet peering to MZ established
- [ ] Private DNS zone linked to MZ VNet
- [ ] ArgoCD cluster secret created in MZ cluster
- [ ] Public IP allocated

### Git Repository (GitOps)
- [ ] Region directory created: `platform-cz/<region>/`
- [ ] cert-manager values updated with identity client ID
- [ ] cert-manager ClusterIssuers updated with DNS zone
- [ ] external-secrets values updated with identity client ID  
- [ ] external-secrets ClusterSecretStore updated with Key Vault URL
- [ ] Traefik values updated with load balancer IP
- [ ] AppProject destinations updated in `cz-security.yaml`
- [ ] ArgoCD Applications created in `cz-platform-<region>.yaml`

### Verification
- [ ] ArgoCD shows new cluster as connected
- [ ] All platform Applications synced successfully
- [ ] DNS resolves to correct IP
- [ ] TLS certificates issued successfully

---

## Network Connectivity

### How MZ ArgoCD Reaches CZ Clusters

Terraform sets up the network path:

```
MZ ArgoCD Pod
    │
    ▼
MZ VNet (10.100.x.x)
    │
    │ VNet Peering
    ▼
CZ VNet (10.200.x.x)
    │
    │ Private DNS Zone Link
    ▼
CZ AKS Private API Server
(rex5-cc-cz-prod.rex5-cc-cz-prod-aks.privatelink.canadacentral.azmk8s.io)
```

**Key Terraform resources:**
- `azurerm_virtual_network_peering` — Bidirectional peering
- `azurerm_private_dns_zone_virtual_network_link` — DNS resolution

### Authentication Flow

```
MZ ArgoCD Service Account
    │
    │ Workload Identity (OIDC token)
    ▼
Azure AD Token Exchange
    │
    │ Federated Credential trust
    ▼
CZ ArgoCD Managed Identity
(rex5-cc-cz-prod-<region>-argocd-identity)
    │
    │ AKS Cluster Admin role
    ▼
CZ AKS Cluster
```

**Terraform creates:**
- CZ managed identity with AKS Cluster Admin role
- Federated credential trusting MZ ArgoCD service account
- Cluster secret with kubelogin exec config

---

## Troubleshooting

### ArgoCD can't connect to new cluster

1. **Check cluster secret exists:**
   ```bash
   kubectl get secret -n rex5-cc-mz-k8s-argocd | grep <region>
   ```

2. **Check network connectivity (VNet peering):**
   ```bash
   az network vnet peering list --vnet-name <MZ_VNET> -g <MZ_VNET_RG> -o table
   ```

3. **Check DNS resolution:**
   ```bash
   kubectl run test-dns -n rex5-cc-mz-k8s-argocd --rm -it --restart=Never \
     --image=busybox -- nslookup <CZ_AKS_PRIVATE_FQDN>
   ```

4. **Check federated credential:**
   ```bash
   az identity federated-credential list \
     --identity-name rex5-cc-cz-prod-<region>-argocd-identity \
     --resource-group <IDENTITY_RG> -o table
   ```

5. **Check ArgoCD logs:**
   ```bash
   kubectl logs -n rex5-cc-mz-k8s-argocd -l app.kubernetes.io/name=argocd-application-controller | grep -i error
   ```

### cert-manager can't solve DNS-01 challenges

1. Verify managed identity has DNS Zone Contributor role
2. Check federated credential issuer URL matches AKS OIDC issuer
3. Check cert-manager logs:
   ```bash
   kubectl logs -n rex5-cc-cz-k8s-cert-manager -l app.kubernetes.io/name=cert-manager
   ```

### external-secrets can't read from Key Vault

1. Verify managed identity has Key Vault Secrets User role
2. Check Key Vault network access (private endpoint or allow Azure services)
3. Check external-secrets logs:
   ```bash
   kubectl logs -n rex5-cc-cz-k8s-external-secrets -l app.kubernetes.io/name=external-secrets
   ```

---

## Reference: canadacentral Configuration

The `canadacentral` region serves as the reference implementation:

| Component | Value |
|-----------|-------|
| AKS Cluster | `rex5-cc-cz-prod-aks` |
| AKS Private FQDN | `rex5-cc-cz-prod.rex5-cc-cz-prod-aks.privatelink.canadacentral.azmk8s.io` |
| Cluster Secret Name | `rex5-cc-cz-prod` (Terraform-managed) |
| ArgoCD Identity | `rex5-cc-cz-prod-argocd-identity` |
| ArgoCD Identity Client ID | `63de6227-6397-4376-bb12-741e739440f0` |
| Key Vault | See `environments/cz/config.yaml` |
| DNS Zone | `cz.cc.rex5.ca` |

---

## Contact

For questions about CZ platform onboarding, contact the Platform team.
