# Hubble Observability for AKS with Azure CNI Powered by Cilium

This deploys **Hubble Relay and UI only** - not the full Cilium stack. Azure manages the Cilium CNI, this just adds the observability layer.

## What This Deploys

| Component | Purpose |
|-----------|---------|
| Hubble Relay | Aggregates flow data from Cilium agents on all nodes |
| Hubble UI | Web interface for visualizing network flows |

## Prerequisites

- AKS cluster with `network_data_plane = "cilium"` (Azure CNI Powered by Cilium)
- Cilium agents running (Azure manages these in `kube-system`)

## Verify Azure-Managed Cilium is Running

```bash
# Check Cilium pods (managed by Azure)
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status
```

## ArgoCD Deployment

Hubble is deployed via ArgoCD at **sync wave 1** (after namespaces).

The ArgoCD Application deploys to `kube-system` namespace where Cilium runs.

## Accessing Hubble UI

### Option 1: Port Forward (Quick Test)
```bash
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
# Open http://localhost:8080
```

### Option 2: Via Traefik HTTPRoute (Production)
Uncomment the HTTPRoute in `kustomization.yaml` and create `httproute.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  parentRefs:
    - name: shared-gateway
      namespace: rex5-cc-cz-k8s-traefik
  hostnames:
    - "hubble.cz.cc.rex5.ca"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: hubble-ui
          port: 80
```

## Using Hubble CLI

```bash
# Install Hubble CLI
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-amd64.tar.gz
tar xzvf hubble-linux-amd64.tar.gz
sudo mv hubble /usr/local/bin/

# Port-forward to Hubble Relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &

# Observe flows
hubble observe --follow
hubble observe --namespace rex5-cc-cz-k8s-traefik
hubble observe --verdict DROPPED
```

## Troubleshooting

### Hubble Relay Can't Connect to Agents
```bash
# Check if Cilium agents have Hubble enabled
kubectl exec -n kube-system ds/cilium -- cilium status | grep Hubble

# If Hubble is disabled on agents, you may need Azure CLI:
az aks update -g <RG> -n <AKS> --enable-hubble
```

### Check Hubble Relay Logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=hubble-relay
```

### Check Hubble UI Logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=hubble-ui
```

## Version

- Cilium/Hubble Chart Version: 1.17.12
- Hubble Relay: v1.17.12
- Hubble UI: v0.13.1

**Important**: Match Hubble version to Azure-managed Cilium:
| AKS Version | Cilium Version | Chart Version |
|-------------|----------------|---------------|
| 1.31 | 1.16.6 | 1.16.6 |
| 1.32+ | 1.17.0 | 1.17.12 |
