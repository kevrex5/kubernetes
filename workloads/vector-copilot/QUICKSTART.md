# Vector Copilot Quick Start

## Chart Structure
```
vector-copilot/
├── Chart.yaml                 # Helm chart metadata
├── values.yaml               # Default configuration values
├── templates/
│   ├── _helpers.tpl         # Template helper functions
│   ├── serviceaccount.yaml  # ServiceAccount for Vector
│   ├── configmap.yaml       # Vector configuration (vector.yaml)
│   ├── deployment.yaml      # Vector Deployment
│   ├── service.yaml         # Service exposing port 6514
│   ├── pvc.yaml            # PersistentVolumeClaim for disk buffer
│   └── NOTES.txt           # Post-install instructions
├── .helmignore             # Files to ignore in Helm package
└── README.md               # Complete documentation

```

## Key Features Implemented

✅ **Syslog TLS Ingestion** - Port 6514 with certificate/key from Kubernetes secret
✅ **CEF Parsing & Filtering** - Only forwards CEF-formatted messages
✅ **Hash-based Load Splitting** - 50/50 distribution to two Azure DCR endpoints
✅ **Disk Buffering** - 50Gi PVC with 20GB max buffer for reliability
✅ **Production Security** - Non-root user, read-only filesystem where possible
✅ **Health Checks** - Liveness/readiness probes on Vector API (port 8686)
✅ **Values-driven** - All configuration externalized to values.yaml

## Vector Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│ Syslog TLS Source (0.0.0.0:6514)                               │
│ - TLS with cert from /etc/vector/tls/                          │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Transform: parse_syslog                                         │
│ - Parse syslog format                                           │
│ - Add .meta.port_received = 6514                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Transform: filter_cef                                           │
│ - Only pass events where .message starts with "CEF:"            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Transform: compute_hash                                         │
│ - Build key from .host + .appname + .message                    │
│ - hash = crc32(key)                                             │
│ - .route.hash_bucket = hash % 2                                 │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ├──────────────────────┬──────────────────────┤
                     ▼                      ▼
        ┌────────────────────┐  ┌────────────────────┐
        │ route_dcr1         │  │ route_dcr2         │
        │ (bucket == 0)      │  │ (bucket == 1)      │
        └──────┬─────────────┘  └─────────┬──────────┘
               │                          │
               ▼                          ▼
    ┌──────────────────┐      ┌──────────────────┐
    │ Sink: azure_dcr1 │      │ Sink: azure_dcr2 │
    │ - HTTP POST      │      │ - HTTP POST      │
    │ - Bearer auth    │      │ - Bearer auth    │
    │ - Gzip compress  │      │ - Gzip compress  │
    │ - Disk buffer    │      │ - Disk buffer    │
    │ - Retry logic    │      │ - Retry logic    │
    └──────────────────┘      └──────────────────┘
```

## Deployment Steps

### 1. Prerequisites
```bash
# Create namespace
kubectl create namespace rex5-cc-mz-k8s-vector

# Create TLS secret
kubectl create secret tls vector-tls \
  --cert=vector-server.crt \
  --key=vector-server.key \
  -n rex5-cc-mz-k8s-vector

# Create Azure DCR token secret
kubectl create secret generic azure-dcr-token \
  --from-literal=token='YOUR_BEARER_TOKEN_HERE' \
  -n rex5-cc-mz-k8s-vector
```

### 2. Configure Values
Create `production-values.yaml`:

```yaml
# Update with your Azure DCR endpoints
dcr:
  dcr1:
    uri: "https://dce-prod.ingest.monitor.azure.com/dataCollectionRules/dcr-abc123/streams/Custom-SyslogCEF_CL?api-version=2023-01-01"
    name: "dcr-prod-primary"
  dcr2:
    uri: "https://dce-prod.ingest.monitor.azure.com/dataCollectionRules/dcr-def456/streams/Custom-SyslogCEF_CL?api-version=2023-01-01"
    name: "dcr-prod-secondary"

# Expose via LoadBalancer for external syslog sources
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "rex5-cc-mz-prod-publicip-rg"

# Production resources
resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

# Spot node tolerations if needed
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule

# Storage class
persistence:
  storageClassName: managed-csi-premium
  size: 50Gi
```

### 3. Install
```bash
helm install vector-copilot ./workloads/vector-copilot \
  -n rex5-cc-mz-k8s-vector \
  -f production-values.yaml
```

### 4. Verify
```bash
# Check pods
kubectl get pods -n rex5-cc-mz-k8s-vector

# Check service (wait for LoadBalancer IP)
kubectl get svc -n rex5-cc-mz-k8s-vector

# Check logs
kubectl logs -n rex5-cc-mz-k8s-vector -l app.kubernetes.io/name=vector-copilot -f

# Test health endpoint
kubectl port-forward -n rex5-cc-mz-k8s-vector svc/vector-copilot 8686:8686
curl http://localhost:8686/health
```

### 5. Test Syslog Ingestion
```bash
# Get LoadBalancer IP
LB_IP=$(kubectl get svc -n rex5-cc-mz-k8s-vector vector-copilot -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Send test CEF message
echo '<134>1 2026-01-22T12:00:00.000Z testhost testapp 1234 ID1 - CEF:0|Security|Firewall|1.0|100|Connection Denied|5| src=10.0.0.1 dst=192.168.1.1 spt=12345 dpt=443' | \
  openssl s_client -connect $LB_IP:6514 -quiet -no_ign_eof
```

## Configuration Details

### Hash Splitting
The chart uses a stable hash function to distribute events:
- Hash key = `.host` + `.appname` + `.message`
- CRC32 hash % 2 determines bucket (0 or 1)
- Ensures consistent routing for same source

**Why these fields?**
- `.host` - Source hostname
- `.appname` - Application name from syslog
- `.message` - Message content (CEF payload)

This combination ensures events from the same host/app are routed consistently while distributing load across both DCRs.

### Buffer Configuration
- **Type**: Disk (persistent across restarts)
- **Max Size**: 20GB (configurable via `buffer.maxSizeBytes`)
- **When Full**: Block (backpressure, don't drop data)
- **Location**: `/var/lib/vector` (mounted from 50Gi PVC)

### HTTP Sink Settings
- **Concurrency**: 4 parallel requests per sink
- **Timeout**: 30 seconds
- **Compression**: gzip (reduces bandwidth)
- **Batch Size**: 900KB (under Azure 1MB limit)
- **Batch Timeout**: 1 second
- **Retries**: 5 attempts with exponential backoff

### Security
- Runs as non-root user (UID 1000)
- No privilege escalation
- TLS certificates mounted read-only
- Token from Kubernetes secret (never in Git)

## Troubleshooting

### No events in Azure
1. Check Vector logs: `kubectl logs -n rex5-cc-mz-k8s-vector -l app.kubernetes.io/name=vector-copilot`
2. Verify DCR URIs are correct (check values.yaml)
3. Ensure token is valid: `kubectl get secret azure-dcr-token -n rex5-cc-mz-k8s-vector -o yaml`
4. Test connectivity: `kubectl exec -n rex5-cc-mz-k8s-vector <pod> -- curl -v <DCR_URI>`

### TLS errors
1. Verify cert/key exist: `kubectl get secret vector-tls -n rex5-cc-mz-k8s-vector`
2. Check cert validity: `kubectl get secret vector-tls -n rex5-cc-mz-k8s-vector -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text`
3. Test TLS handshake: `openssl s_client -connect <LB_IP>:6514 -showcerts`

### Buffer filling up
1. Check disk usage: `kubectl exec -n rex5-cc-mz-k8s-vector <pod> -- df -h /var/lib/vector`
2. Check PVC size: `kubectl get pvc -n rex5-cc-mz-k8s-vector`
3. Increase `persistence.size` or `buffer.maxSizeBytes` if needed

### Performance issues
1. Increase `resources.limits.cpu` and `resources.limits.memory`
2. Increase `http.concurrency` for more parallel requests
3. Adjust `http.batchMaxBytes` and `http.batchTimeoutSeconds` for better batching

## Next Steps

1. **Add to ArgoCD**: Create ArgoCD Application to manage this chart
2. **Monitoring**: Add ServiceMonitor for Prometheus metrics (Vector exposes metrics on :8686/metrics)
3. **Alerting**: Set up alerts for buffer usage, error rates, and throughput
4. **Gateway API**: Add HTTPRoute or TCPRoute for routing (if using Traefik/Gateway API)
5. **NetworkPolicy**: Add policies to restrict ingress/egress

## GitOps Integration

To add this to your ArgoCD-managed platform:

```yaml
# apps/vector-copilot/Chart.yaml (Argo app-of-apps pattern)
apiVersion: v2
name: vector-copilot
version: 1.0.0
dependencies:
  - name: vector-copilot
    version: 1.0.0
    repository: file://../../workloads/vector-copilot

# apps/vector-copilot/values.yaml
vector-copilot:
  dcr:
    dcr1:
      uri: "https://..."
    dcr2:
      uri: "https://..."
  # ... other overrides
```

Or use ArgoCD multi-source pattern:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vector-copilot
  namespace: rex5-cc-mz-k8s-argocd
spec:
  project: platform
  sources:
    - repoURL: git@github.com:kevrex5/kubernetes.git
      targetRevision: main
      path: workloads/vector-copilot
      helm:
        valueFiles:
          - $values/apps/vector-copilot/values.yaml
    - repoURL: git@github.com:kevrex5/kubernetes.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: rex5-cc-mz-k8s-vector
```
