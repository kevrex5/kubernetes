# Vector Deployment Guide

Quick reference for deploying Vector syslog collectors to Kubernetes via ArgoCD.

## Charts Overview

| Chart | Purpose | Key Features |
|-------|---------|--------------|
| **vector-default** | Baseline starter | Minimal syslog TCP listener, no TLS, stdout sink |
| **vector-azure-simple** | Single destination | TLS syslog → Azure Log Analytics (single DCR) |
| **vector-claude** | Dual destination | TLS syslog → CEF parsing → aggregation → 50/50 split to 2 DCRs |
| **vector-copilot** | Advanced routing | TLS syslog → CEF filtering → hash-based splitting to 2 DCRs |

**Recommendation**: Start with `vector-azure-simple` for production, use `vector-claude` for high-volume CEF aggregation.

---

## Prerequisites

### 1. Secrets Required

All charts need secrets created **before** deployment:

```bash
# Create namespace
kubectl create namespace rex5-cc-mz-k8s-vector

# TLS certificate for syslog ingestion (not needed for vector-default)
kubectl create secret tls vector-syslog-tls \
  --cert=/path/to/server.crt \
  --key=/path/to/server.key \
  -n rex5-cc-mz-k8s-vector

# Azure DCR ingestion token
kubectl create secret generic azure-ingest-token \
  --from-literal=token='eyJ0eXAiOiJKV1...' \
  -n rex5-cc-mz-k8s-vector
```

**Getting Azure DCR Token:**
```bash
# Generate token for Data Collection Endpoint (DCE)
az login
TENANT_ID=$(az account show --query tenantId -o tsv)
az rest --method POST \
  --url "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  --headers "Content-Type=application/x-www-form-urlencoded" \
  --body "client_id=YOUR_CLIENT_ID&scope=https://monitor.azure.com/.default&client_secret=YOUR_CLIENT_SECRET&grant_type=client_credentials"
```

### 2. Azure DCR Setup

**Required Azure Resources:**
- Data Collection Endpoint (DCE)
- Data Collection Rule (DCR) with custom stream
- Log Analytics workspace with custom table
- Service Principal with Monitoring Metrics Publisher role

**Get DCR URI:**
```bash
# Format: https://<DCE>.ingest.monitor.azure.com/dataCollectionRules/<DCR-ID>/streams/<Stream>?api-version=2023-01-01

DCE_ENDPOINT=$(az monitor data-collection endpoint show -n <DCE_NAME> -g <RG> --query logsIngestion.endpoint -o tsv)
DCR_IMMUTABLE_ID=$(az monitor data-collection rule show -n <DCR_NAME> -g <RG> --query immutableId -o tsv)

echo "${DCE_ENDPOINT}/dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/Custom-<TableName>_CL?api-version=2023-01-01"
```

---

## Deployment via ArgoCD

### Option 1: ArgoCD Application YAML (Recommended)

Create Application manifest in your GitOps repo:

```yaml
# argocd/apps/vector-azure-simple.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vector-azure-simple
  namespace: rex5-cc-mz-k8s-argocd
spec:
  project: platform
  source:
    repoURL: git@github.com:kevrex5/kubernetes.git
    targetRevision: main
    path: workloads/vector-azure-simple
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: azure.dcrUri
          value: "https://dce-prod.eastus-1.ingest.monitor.azure.com/dataCollectionRules/dcr-xxx/streams/Custom-SyslogCEF_CL?api-version=2023-01-01"
        - name: service.type
          value: LoadBalancer
        - name: persistence.storageClassName
          value: managed-csi-premium
  destination:
    server: https://kubernetes.default.svc
    namespace: rex5-cc-mz-k8s-vector
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**Apply:**
```bash
kubectl apply -f argocd/apps/vector-azure-simple.yaml
argocd app sync vector-azure-simple
```

### Option 2: ArgoCD CLI

```bash
argocd app create vector-azure-simple \
  --project platform \
  --repo git@github.com:kevrex5/kubernetes.git \
  --path workloads/vector-azure-simple \
  --dest-namespace rex5-cc-mz-k8s-vector \
  --dest-server https://kubernetes.default.svc \
  --helm-set azure.dcrUri="https://dce.ingest.monitor.azure.com/..." \
  --helm-set service.type=LoadBalancer \
  --sync-policy automated \
  --auto-prune \
  --self-heal

argocd app sync vector-azure-simple
```

---

## Configuration Examples

### vector-azure-simple (Single DCR)

```yaml
# Custom values for production
azure:
  dcrUri: "https://dce-prod.eastus-1.ingest.monitor.azure.com/dataCollectionRules/dcr-abc123/streams/Custom-SyslogCEF_CL?api-version=2023-01-01"
  tokenSecretName: "azure-ingest-token"
  tokenSecretKey: "token"

service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "rex5-cc-mz-prod-publicip-rg"

persistence:
  size: "50Gi"
  storageClassName: "managed-csi-premium"

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi

tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
```

### vector-claude (Dual DCR with Aggregation)

```yaml
# CEF aggregation with dual DCR forwarding
dcr:
  dcr1:
    uri: "https://dce1.eastus.ingest.monitor.azure.com/dataCollectionRules/dcr-primary/streams/Custom-CEF_CL?api-version=2023-01-01"
    name: "dcr-primary"
  dcr2:
    uri: "https://dce2.westus.ingest.monitor.azure.com/dataCollectionRules/dcr-secondary/streams/Custom-CEF_CL?api-version=2023-01-01"
    name: "dcr-secondary"

service:
  type: LoadBalancer

buffer:
  maxSizeBytes: 21474836480  # 20GB disk buffer

persistence:
  size: "100Gi"  # Larger for high-volume CEF logs

resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi
```

---

## Verification & Testing

### Check Deployment Status

```bash
# ArgoCD sync status
argocd app get vector-azure-simple

# Pod status
kubectl get pods -n rex5-cc-mz-k8s-vector -l app.kubernetes.io/name=vector-azure-simple

# Service and LoadBalancer IP
kubectl get svc -n rex5-cc-mz-k8s-vector

# Logs
kubectl logs -n rex5-cc-mz-k8s-vector -l app.kubernetes.io/name=vector-azure-simple -f --tail=100
```

### Test Syslog Ingestion

**Get LoadBalancer IP:**
```bash
LB_IP=$(kubectl get svc -n rex5-cc-mz-k8s-vector -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
echo "Vector syslog endpoint: $LB_IP:6514"
```

**Send test message (TLS):**
```bash
# CEF format
echo '<134>1 2026-01-23T12:00:00Z testhost CEF - - - CEF:0|Vendor|Product|1.0|100|Test Event|5| src=10.0.0.1 dst=192.168.1.1 spt=12345 dpt=443 proto=TCP act=blocked' | \
  openssl s_client -connect $LB_IP:6514 -quiet -no_ign_eof

# Syslog format
echo '<134>1 2026-01-23T12:00:00Z testhost testapp 1234 - - Test message from kubectl' | \
  openssl s_client -connect $LB_IP:6514 -quiet -no_ign_eof
```

**For vector-default (no TLS):**
```bash
echo '<134>Jan 23 12:00:00 testhost testapp: Test message' | nc $LB_IP 514
```

### Check Vector Health

```bash
# Port-forward Vector API
kubectl port-forward -n rex5-cc-mz-k8s-vector svc/vector-azure-simple 8686:8686

# Health endpoint
curl http://localhost:8686/health

# Metrics (Prometheus format)
curl http://localhost:8686/metrics | grep vector_

# Configuration (introspection)
curl http://localhost:8686/config
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check events
kubectl describe pod -n rex5-cc-mz-k8s-vector <pod-name>

# Common issues:
# 1. Missing secrets
kubectl get secrets -n rex5-cc-mz-k8s-vector

# 2. PVC not binding
kubectl get pvc -n rex5-cc-mz-k8s-vector
kubectl describe pvc -n rex5-cc-mz-k8s-vector <pvc-name>

# 3. Image pull errors
kubectl get events -n rex5-cc-mz-k8s-vector --sort-by='.lastTimestamp' | tail -20
```

### No Events Reaching Azure

```bash
# 1. Check Vector logs for errors
kubectl logs -n rex5-cc-mz-k8s-vector <pod-name> | grep -i error

# 2. Check sink status (Vector internal metrics)
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- curl -s localhost:8686/metrics | grep -E 'component_sent_events_total|component_errors_total'

# 3. Verify DCR URI is correct
kubectl get configmap -n rex5-cc-mz-k8s-vector -o yaml | grep dcrUri

# 4. Test Azure connectivity
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- curl -v -H "Authorization: Bearer $TOKEN" https://<dce>.ingest.monitor.azure.com/

# 5. Check token validity
kubectl get secret azure-ingest-token -n rex5-cc-mz-k8s-vector -o jsonpath='{.data.token}' | base64 -d | cut -c1-20
```

### TLS Connection Failures

```bash
# 1. Verify certificate exists and is valid
kubectl get secret vector-syslog-tls -n rex5-cc-mz-k8s-vector -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep -E 'Subject:|Not After'

# 2. Test TLS handshake
openssl s_client -connect $LB_IP:6514 -showcerts

# 3. Check certificate matches key
kubectl get secret vector-syslog-tls -n rex5-cc-mz-k8s-vector -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -modulus | md5sum
kubectl get secret vector-syslog-tls -n rex5-cc-mz-k8s-vector -o jsonpath='{.data.tls\.key}' | base64 -d | openssl rsa -noout -modulus | md5sum
# Should produce same hash
```

### High Memory Usage / Buffer Issues

```bash
# 1. Check buffer disk usage
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- df -h /var/lib/vector

# 2. Check PVC size
kubectl get pvc -n rex5-cc-mz-k8s-vector -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage

# 3. Increase buffer size (edit values)
# Edit persistence.size in values.yaml or via ArgoCD parameter

# 4. Check for backpressure (events buffering)
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- curl -s localhost:8686/metrics | grep buffer_events

# 5. Temporary: Clear buffer (DESTRUCTIVE)
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- rm -rf /var/lib/vector/*
kubectl delete pod -n rex5-cc-mz-k8s-vector <pod-name>  # Let it recreate
```

### Performance Issues / Slow Forwarding

```bash
# 1. Check sink throughput
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- curl -s localhost:8686/metrics | grep -E 'component_sent_events_total|component_sent_bytes_total'

# 2. Check for throttling (429 errors from Azure)
kubectl logs -n rex5-cc-mz-k8s-vector <pod-name> | grep -i "429\|throttl\|rate limit"

# 3. Increase concurrency (edit values)
# http.concurrency: 4 → 8 (vector-azure-simple)
# Or adjust batching: http.batchTimeoutSeconds: 1 → 0.5

# 4. Check resource limits
kubectl top pod -n rex5-cc-mz-k8s-vector

# 5. Scale replicas (for high volume)
# Note: Syslog requires sticky sessions or external LB with consistent hashing
kubectl scale deployment -n rex5-cc-mz-k8s-vector vector-azure-simple --replicas=2
```

### Parsing Errors (vector-claude)

```bash
# 1. Check for CEF parse errors
kubectl logs -n rex5-cc-mz-k8s-vector <pod-name> | grep -i "cef_parse_error"

# 2. View raw messages that failed to parse
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- curl -s localhost:8686/tap/parse_cef -X POST | jq '.parse_status, .cef_parse_error'

# 3. Test CEF parsing locally
# Use test/vector-local.yaml for local Vector instance
docker run -it --rm -v $(pwd)/test:/test timberio/vector:0.35.0 \
  --config /test/vector-local.yaml < test/test-messages.txt
```

### ArgoCD Sync Issues

```bash
# 1. Check sync status and errors
argocd app get vector-azure-simple

# 2. View diff between Git and cluster
argocd app diff vector-azure-simple

# 3. Force hard refresh
argocd app get vector-azure-simple --hard-refresh

# 4. Retry failed sync
argocd app sync vector-azure-simple --force

# 5. View sync history
argocd app history vector-azure-simple

# 6. Rollback to previous revision
argocd app rollback vector-azure-simple <revision>
```

---

## Monitoring & Metrics

### Prometheus Integration

Vector exposes Prometheus metrics on port 8686:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vector-metrics
  namespace: rex5-cc-mz-k8s-vector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vector-azure-simple
  endpoints:
    - port: api
      path: /metrics
      interval: 30s
```

**Key metrics to monitor:**
- `vector_component_received_events_total` - Events received by source
- `vector_component_sent_events_total` - Events sent by sinks
- `vector_component_errors_total` - Errors per component
- `vector_buffer_events` - Current buffered events
- `vector_buffer_byte_size` - Buffer size in bytes
- `component_sent_bytes_total` - Bytes sent to Azure

### Grafana Dashboard Queries

```promql
# Event ingestion rate
rate(vector_component_received_events_total{component_name="syslog_tls"}[5m])

# Event forwarding rate
rate(vector_component_sent_events_total{component_type="http"}[5m])

# Error rate
rate(vector_component_errors_total[5m])

# Buffer utilization %
(vector_buffer_byte_size / 21474836480) * 100

# Parse success rate (vector-claude)
rate(vector_component_sent_events_total{component_name="route_cef.ok"}[5m]) / 
rate(vector_component_received_events_total{component_name="parse_cef"}[5m])
```

---

## Maintenance

### Update Chart Version

```bash
# Update image tag in values.yaml
# values.yaml:
#   image:
#     tag: "0.36.0"  # Update version

# Commit and push
git add workloads/vector-azure-simple/values.yaml
git commit -m "chore(vector): update to v0.36.0"
git push

# ArgoCD will auto-sync if automated sync is enabled
# Or manually sync:
argocd app sync vector-azure-simple
```

### Rotate TLS Certificate

```bash
# 1. Create new secret with updated cert
kubectl create secret tls vector-syslog-tls-new \
  --cert=new-server.crt \
  --key=new-server.key \
  -n rex5-cc-mz-k8s-vector

# 2. Update values to use new secret name
# Or replace existing secret:
kubectl delete secret vector-syslog-tls -n rex5-cc-mz-k8s-vector
kubectl create secret tls vector-syslog-tls \
  --cert=new-server.crt \
  --key=new-server.key \
  -n rex5-cc-mz-k8s-vector

# 3. Restart pods to load new cert
kubectl rollout restart deployment -n rex5-cc-mz-k8s-vector
```

### Backup & Recovery

```bash
# Backup Vector data directory (buffer)
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- tar czf - /var/lib/vector > vector-backup-$(date +%Y%m%d).tar.gz

# Backup PVC with Velero (if installed)
velero backup create vector-pvc-backup --include-namespaces rex5-cc-mz-k8s-vector --include-resources pvc,pv

# Restore from backup
kubectl exec -n rex5-cc-mz-k8s-vector <pod-name> -- tar xzf - -C / < vector-backup-20260123.tar.gz
```

---

## Direct Helm Deployment (Non-ArgoCD)

For testing or non-GitOps environments:

```bash
# Install
helm install vector-azure ./workloads/vector-azure-simple -n rex5-cc-mz-k8s-vector \
  --set azure.dcrUri="https://..." \
  --create-namespace

# Upgrade
helm upgrade vector-azure ./workloads/vector-azure-simple -n rex5-cc-mz-k8s-vector \
  --set azure.dcrUri="https://..."

# Rollback
helm rollback vector-azure -n rex5-cc-mz-k8s-vector

# Uninstall
helm uninstall vector-azure -n rex5-cc-mz-k8s-vector
```
