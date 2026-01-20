# Traefik Installation

<!-- NOTE: All platform components should have a README.md with bootstrap/install commands -->

## Prerequisites

- AKS cluster access configured
- Helm v3 installed
- kubectl configured with cluster context
- Azure Static Public IP provisioned
- Traefik namespace created

## Bootstrap Commands

```bash
# 1. Add Helm repo (if not already added)
helm repo add traefik https://traefik.github.io/charts
helm repo update

# 2. Create namespace
kubectl apply -f ../../namespaces/traefik.yaml

# 3. Install Traefik with values
helm install traefik traefik/traefik -n rex5-cc-mz-k8s-traefik -f values.yaml --timeout 10m

# 4. Verify installation
kubectl get pods -n rex5-cc-mz-k8s-traefik
kubectl get svc -n rex5-cc-mz-k8s-traefik

# 5. Get LoadBalancer IP
kubectl get svc traefik -n rex5-cc-mz-k8s-traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Post-Bootstrap: Apply Runtime Resources

After Traefik is running, ArgoCD will manage the runtime resources:
- Gateway and GatewayClass (Gateway API)
- ExternalSecrets (credentials + wildcard cert from Key Vault)
- NetworkPolicies

These are applied via the kustomization in `platform/traefik/`.

## Configuration

### Load Balancer
- **Type**: Azure Standard Load Balancer
- **Public IP**: `4.204.154.192` (pre-provisioned in `rex5-cc-mz-prod-publicip-rg`)
- **DNS**: Configured separately to point `*.rex5.ca` to this IP

### High Availability
- 3 replicas with pod anti-affinity
- Pod disruption budget (minAvailable: 2)
- Spot node tolerations for cost optimization

### Gateway API
- Uses Kubernetes Gateway API (not IngressRoute CRDs)
- Shared Gateway in `traefik` namespace
- Cross-namespace routing via `allowedRoutes` selector

### TLS
- Wildcard certificate (`*.rex5.ca`) from cert-manager
- Stored in Azure Key Vault, distributed via External Secrets Operator
- Automatic TLS termination at Gateway

## Upgrade

```bash
# Check for chart updates
helm repo update
helm search repo traefik/traefik --versions | head

# Upgrade with values
helm upgrade traefik traefik/traefik -n rex5-cc-mz-k8s-traefik -f values.yaml --timeout 10m

# Rollback if needed
helm rollback traefik -n rex5-cc-mz-k8s-traefik
```

## Troubleshooting

### LoadBalancer not getting external IP
```bash
kubectl describe svc traefik -n rex5-cc-mz-k8s-traefik
kubectl get events -n rex5-cc-mz-k8s-traefik --sort-by=.metadata.creationTimestamp
```

### Gateway not ready
```bash
kubectl get gateway -n rex5-cc-mz-k8s-traefik
kubectl describe gateway shared-gateway -n rex5-cc-mz-k8s-traefik
```

### TLS certificate issues
```bash
kubectl get externalsecret -n rex5-cc-mz-k8s-traefik
kubectl get secret wildcard-tls -n rex5-cc-mz-k8s-traefik
kubectl describe externalsecret wildcard-tls -n rex5-cc-mz-k8s-traefik
```

## Uninstall

```bash
helm uninstall traefik -n rex5-cc-mz-k8s-traefik
kubectl delete namespace rex5-cc-mz-k8s-traefik
```

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm values for Traefik installation |
| `../gateway.yaml` | GatewayClass and shared Gateway |
| `../externalsecret.yaml` | Traefik dashboard credentials (if used) |
| `../externalsecret-wildcard.yaml` | Wildcard TLS cert from Key Vault |
| `../networkpolicies.yaml` | Network policies for Traefik |
| `../kustomization.yaml` | Kustomize for runtime resources |

## Related

- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Azure Load Balancer Annotations](https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard)
