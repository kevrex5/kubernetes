# ArgoCD Installation

<!-- NOTE: All platform components should have a README.md with bootstrap/install commands -->

## Prerequisites

- AKS cluster access configured
- Helm v3 installed
- kubectl configured with cluster context
- Azure CLI (`az`) configured with access to Key Vault
- GitHub repository created at `https://github.com/kevrex5/kubernetes`

## Setup GitHub Repository & SSH Key

Before installing ArgoCD, configure Git repository authentication:

```bash
# 1. Create GitHub repository (if not already done)
# Via web: https://github.com/new
# Or via CLI: gh repo create kevrex5/kubernetes --private

# 2. Get the SSH public key from Key Vault (already generated)
az keyvault secret show --vault-name rex5-cc-mz-prod-kv \
  --name argocd-git-ssh-private-key \
  --query "value" -o tsv | ssh-keygen -y -f /dev/stdin

# 3. Add the public key as a GitHub deploy key
# Go to: https://github.com/kevrex5/kubernetes/settings/keys
# - Click "Add deploy key"
# - Title: "ArgoCD Production Cluster"
# - Paste the public key from step 2
# - Leave "Allow write access" unchecked (read-only)

# 4. Create temporary ArgoCD repository credentials secret
az keyvault secret show --vault-name rex5-cc-mz-prod-kv \
  --name argocd-git-ssh-private-key \
  --query "value" -o tsv > /tmp/argocd-ssh-key

kubectl create secret generic argocd-repo-creds \
  -n rex5-cc-mz-k8s-argocd \
  --from-file=sshPrivateKey=/tmp/argocd-ssh-key \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret argocd-repo-creds \
  -n rex5-cc-mz-k8s-argocd \
  argocd.argoproj.io/secret-type=repository

# Clean up temporary file
rm /tmp/argocd-ssh-key

# 5. Push your code to GitHub
cd /home/krichar/kubernetes
git remote add origin git@github.com:kevrex5/kubernetes.git
git push -u origin master
```

## Bootstrap Commands

```bash
# 1. Add Helm repo (if not already added)
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Create namespace
kubectl create namespace argocd

# 3. Install ArgoCD with values
helm install argocd argo/argo-cd -n rex5-cc-mz-k8s-argocd -f values.yaml

# 4. Get initial admin password
kubectl -n rex5-cc-mz-k8s-argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# 5. Port-forward to access UI (temporary, until HTTPRoute is configured)
kubectl port-forward svc/argocd-server -n rex5-cc-mz-k8s-argocd 8080:443
```

Access UI at `https://localhost:8080` with username `admin`.

## Post-Bootstrap: Enable GitOps

Once ArgoCD is running, apply AppProjects and the root application to enable GitOps:

```bash
# 1. Apply AppProjects (define RBAC boundaries)
kubectl apply -f ../projects/platform.yaml
kubectl apply -f ../projects/apps.yaml

# 2. Apply root application (triggers app-of-apps pattern)
kubectl apply -f ../apps/root.yaml

# 3. Monitor ArgoCD applications
kubectl get applications -n rex5-cc-mz-k8s-argocd -w

# Or use ArgoCD CLI:
argocd app list
argocd app get root
```

This bootstraps the app-of-apps pattern and ArgoCD will manage everything from Git.

### What Gets Deployed Automatically

After applying the root app, ArgoCD will automatically deploy (in order via sync waves):

- **Wave -1**: Namespaces (all platform & app namespaces)
- **Wave 0**: Shared resources (wildcard certificates)
- **Wave 1**: cert-manager (certificate issuance)
- **Wave 2**: external-secrets (secrets from Key Vault)
- **Wave 3**: Traefik (ingress controller + Gateway)
- **Wave 4**: Authentik (SSO/IdP)
- **Wave 5**: Monitoring (Prometheus, Grafana, Alertmanager)
- **Wave 6+**: Application workloads (auto-discovered from `apps/`)

### External Secrets Takeover

The temporary `argocd-repo-creds` secret will be replaced by External Secrets Operator once it's deployed:

```bash
# Verify ExternalSecret is syncing (after external-secrets is deployed)
kubectl get externalsecret argocd-repo-creds -n rex5-cc-mz-k8s-argocd
kubectl describe externalsecret argocd-repo-creds -n rex5-cc-mz-k8s-argocd

# The secret will now be automatically updated from Key Vault
```

## Upgrade

```bash
helm upgrade argocd argo/argo-cd -n rex5-cc-mz-k8s-argocd -f values.yaml
```

## Uninstall

```bash
helm uninstall argocd -n rex5-cc-mz-k8s-argocd
kubectl delete namespace rex5-cc-mz-k8s-argocd
```

## Troubleshooting

### ArgoCD can't connect to Git repository

```bash
# Check repository credentials secret
kubectl get secret argocd-repo-creds -n rex5-cc-mz-k8s-argocd
kubectl describe secret argocd-repo-creds -n rex5-cc-mz-k8s-argocd

# Test SSH connection from ArgoCD server pod
kubectl exec -it deployment/argocd-server -n rex5-cc-mz-k8s-argocd -- ssh -T git@github.com

# Check if deploy key is added to GitHub
# Go to: https://github.com/kevrex5/kubernetes/settings/keys
```

### Applications stuck in "Unknown" or "OutOfSync" state

```bash
# Check Application status
argocd app get <app-name>

# Force sync
argocd app sync <app-name>

# Check ArgoCD application controller logs
kubectl logs -n rex5-cc-mz-k8s-argocd -l app.kubernetes.io/name=argocd-application-controller
```

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for ArgoCD installation (spot tolerations, HA config) |
| `httproute.yaml` | Gateway API route for external access (argocd.rex5.ca) |
| `externalsecret.yaml` | ExternalSecret for Git SSH credentials from Key Vault |
| `kustomization.yaml` | Kustomize manifest for additional resources |

## Related

- [ArgoCD Helm Chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
