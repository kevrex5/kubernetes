# ArgoCD Installation

<!-- NOTE: All platform components should have a README.md with bootstrap/install commands -->

## Prerequisites

- AKS cluster access configured
- Helm v3 installed
- kubectl configured with cluster context

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

Once ArgoCD is running, apply the root application to enable GitOps:

```bash
kubectl apply -f ../apps/root.yaml
```

This bootstraps the app-of-apps pattern and ArgoCD will manage everything from Git.

## Upgrade

```bash
helm upgrade argocd argo/argo-cd -n rex5-cc-mz-k8s-argocd -f values.yaml
```

## Uninstall

```bash
helm uninstall argocd -n rex5-cc-mz-k8s-argocd
kubectl delete namespace rex5-cc-mz-k8s-argocd
```

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for ArgoCD installation |
| `httproute.yaml` | Gateway API route for external access |
| `kustomization.yaml` | Kustomize manifest for additional resources |

## Related

- [ArgoCD Helm Chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
