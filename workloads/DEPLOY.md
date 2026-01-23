# Vector Deployment Guide

Quick reference for deploying Vector syslog collectors to Kubernetes via ArgoCD.

## Environment Variables

Set these variables for your environment:

```bash
# Core configuration
export VECTOR_NAMESPACE="rex5-cc-mz-k8s-vector"
export ARGOCD_NAMESPACE="rex5-cc-mz-k8s-argocd"
export GIT_REPO="git@github.com:kevrex5/kubernetes.git"
export GIT_BRANCH="main"

# Secrets
export TLS_SECRET_NAME="vector-syslog-tls"
export AZURE_TOKEN_SECRET="azure-ingest-token"

# Azure resources
export AZURE_DCE_NAME="dce-prod"
export AZURE_DCE_REGION="eastus-1"
export AZURE_DCR_NAME="dcr-syslog-prod"
export AZURE_DCR_RG="rex5-cc-mz-prod-rg"
export AZURE_TABLE_NAME="SyslogCEF"

# Storage
export STORAGE_CLASS="managed-csi-premium"
export LB_RESOURCE_GROUP="rex5-cc-mz-prod-publicip-rg"

# App names
export VECTOR_APP_NAME="vector-azure-simple"  # or vector-claude, vector-default
```

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
kubectl create namespace $VECTOR_NAMESPACE

# TLS certificate for syslog ingestion (not needed for vector-default)
kubectl create secret tls $TLS_SECRET_NAME \
  --cert=/path/to/server.crt \
  --key=/path/to/server.key \
  -n $VECTOR_NAMESPACE

# Azure DCR ingestion token
kubectl create secret generic $AZURE_TOKEN_SECRET \
  --from-literal=token='eyJ0eXAiOiJKV1...' \
  -n $VECTOR_NAMESPACE
```

**Getting Azure DCR Token:**
```bash
# Set Azure credentials
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"

# Generate token for Data Collection Endpoint (DCE)
az login
export TENANT_ID=$(az account show --query tenantId -o tsv)
export AZURE_TOKEN=$(az rest --method POST \
  --url "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  --headers "Content-Type=application/x-www-form-urlencoded" \
  --body "client_id=${AZURE_CLIENT_ID}&scope=https://monitor.azure.com/.default&client_secret=${AZURE_CLIENT_SECRET}&grant_type=client_credentials" \
  --query access_token -o tsv)

echo "Token: $AZURE_TOKEN"
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

export DCE_ENDPOINT=$(az monitor data-collection endpoint show -n $AZURE_DCE_NAME -g $AZURE_DCR_RG --query logsIngestion.endpoint -o tsv)
export DCR_IMMUTABLE_ID=$(az monitor data-collection rule show -n $AZURE_DCR_NAME -g $AZURE_DCR_RG --query immutableId -o tsv)
export DCR_URI="${DCE_ENDPOINT}/dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/Custom-${AZURE_TABLE_NAME}_CL?api-version=2023-01-01"

echo "DCR URI: $DCR_URI"
```

---

## Deployment via ArgoCD

### Option 1: ArgoCD Application YAML (Recommended)

Create Application manifest in your GitOps repo:

```bash
# Generate Application manifest
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $VECTOR_APP_NAME
  namespace: $ARGOCD_NAMESPACE
spec:
  project: platform
  source:
    repoURL: $GIT_REPO
    targetRevision: $GIT_BRANCH
    path: workloads/$VECTOR_APP_NAME
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: azure.dcrUri
          value: "$DCR_URI"
        - name: service.type
          value: LoadBalancer
        - name: persistence.storageClassName
          value: $STORAGE_CLASS
  destination:
    server: https://kubernetes.default.svc
    namespace: $VECTOR_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

# Sync application
argocd app sync $VECTOR_APP_NAME
```

### Option 2: ArgoCD CLI

```bash
argocd app create $VECTOR_APP_NAME \
  --project platform \
  --repo $GIT_REPO \
  --path workloads/$VECTOR_APP_NAME \
  --dest-namespace $VECTOR_NAMESPACE \
  --dest-server https://kubernetes.default.svc \
  --helm-set azure.dcrUri="$DCR_URI" \
  --helm-set service.type=LoadBalancer \
  --helm-set persistence.storageClassName=$STORAGE_CLASS \
  --sync-policy automated \
  --auto-prune \
  --self-heal

argocd app sync $VECTOR_APP_NAME
```

---

## Configuration Examples

### vector-azure-simple (Single DCR)

```bash
# Create custom values file
cat <<EOF > /tmp/vector-prod-values.yaml
azure:
  dcrUri: "$DCR_URI"
  tokenSecretName: "$AZURE_TOKEN_SECRET"
  tokenSecretKey: "token"

service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "$LB_RESOURCE_GROUP"

persistence:
  size: "50Gi"
  storageClassName: "$STORAGE_CLASS"

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
EOF

cat /tmp/vector-prod-values.yaml
```

### vector-claude (Dual DCR with Aggregation)

```bash
# Set secondary DCR (optional for dual setup)
export DCR_URI_2="${DCE_ENDPOINT}/dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/Custom-${AZURE_TABLE_NAME}_CL?api-version=2023-01-01"

# Create custom values file
cat <<EOF > /tmp/vector-claude-values.yaml
dcr:
  dcr1:
    uri: "$DCR_URI"
    name: "dcr-primary"
  dcr2:
    uri: "$DCR_URI_2"
    name: "dcr-secondary"

service:
  type: LoadBalancer

buffer:
  maxSizeBytes: 21474836480  # 20GB disk buffer

persistence:
  size: "100Gi"  # Larger for high-volume CEF logs
  storageClassName: "$STORAGE_CLASS"

resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi

tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
EOF

cat /tmp/vector-claude-values.yaml
```

---

## Verification & Testing

### Check Deployment Status

```bash
# ArgoCD sync status
argocd app get $VECTOR_APP_NAME

# Pod status
kubectl get pods -n $VECTOR_NAMESPACE -l app.kubernetes.io/name=$VECTOR_APP_NAME

# Service and LoadBalancer IP
kubectl get svc -n $VECTOR_NAMESPACE

# Logs
kubectl logs -n $VECTOR_NAMESPACE -l app.kubernetes.io/name=$VECTOR_APP_NAME -f --tail=100
```

### Test Syslog Ingestion

**Get LoadBalancer IP:**
```bash
export LB_IP=$(kubectl get svc -n $VECTOR_NAMESPACE -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
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
kubectl port-forward -n $VECTOR_NAMESPACE svc/$VECTOR_APP_NAME 8686:8686 &
export PF_PID=$!

# Wait for port-forward
sleep 2

# Health endpoint
curl http://localhost:8686/health

# Metrics (Prometheus format)
curl http://localhost:8686/metrics | grep vector_

# Configuration (introspection)
curl http://localhost:8686/config

# Stop port-forward
kill $PF_PID 2>/dev/null
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Get pod name
export POD_NAME=$(kubectl get pods -n $VECTOR_NAMESPACE -l app.kubernetes.io/name=$VECTOR_APP_NAME -o jsonpath='{.items[0].metadata.name}')

# Check events
kubectl describe pod -n $VECTOR_NAMESPACE $POD_NAME

# Common issues:
# 1. Missing secrets
kubectl get secrets -n $VECTOR_NAMESPACE

# 2. PVC not binding
kubectl get pvc -n $VECTOR_NAMESPACE
export PVC_NAME=$(kubectl get pvc -n $VECTOR_NAMESPACE -o jsonpath='{.items[0].metadata.name}')
kubectl describe pvc -n $VECTOR_NAMESPACE $PVC_NAME

# 3. Image pull errors
kubectl get events -n $VECTOR_NAMESPACE --sort-by='.lastTimestamp' | tail -20
```

### No Events Reaching Azure

```bash
# 1. Check Vector logs for errors
kubectl logs -n $VECTOR_NAMESPACE $POD_NAME | grep -i error

# 2. Check sink status (Vector internal metrics)
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- curl -s localhost:8686/metrics | grep -E 'component_sent_events_total|component_errors_total'

# 3. Verify DCR URI is correct
kubectl get configmap -n $VECTOR_NAMESPACE -o yaml | grep -i uri

# 4. Test Azure connectivity
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- curl -v -H "Authorization: Bearer $AZURE_TOKEN" ${DCE_ENDPOINT}/

# 5. Check token validity
export TOKEN_PREVIEW=$(kubectl get secret $AZURE_TOKEN_SECRET -n $VECTOR_NAMESPACE -o jsonpath='{.data.token}' | base64 -d | cut -c1-20)
echo "Token preview: ${TOKEN_PREVIEW}..."
```

### TLS Connection Failures

```bash
# 1. Verify certificate exists and is valid
kubectl get secret $TLS_SECRET_NAME -n $VECTOR_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep -E 'Subject:|Not After'

# 2. Test TLS handshake
openssl s_client -connect $LB_IP:6514 -showcerts

# 3. Check certificate matches key
export CERT_HASH=$(kubectl get secret $TLS_SECRET_NAME -n $VECTOR_NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -modulus | md5sum)
export KEY_HASH=$(kubectl get secret $TLS_SECRET_NAME -n $VECTOR_NAMESPACE -o jsonpath='{.data.tls\.key}' | base64 -d | openssl rsa -noout -modulus | md5sum)
echo "Cert hash: $CERT_HASH"
echo "Key hash:  $KEY_HASH"
# Should produce same hash
```

### High Memory Usage / Buffer Issues

```bash
# 1. Check buffer disk usage
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- df -h /var/lib/vector

# 2. Check PVC size
kubectl get pvc -n $VECTOR_NAMESPACE -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage

# 3. Increase buffer size (edit values)
# Edit persistence.size in values.yaml or via ArgoCD parameter

# 4. Check for backpressure (events buffering)
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- curl -s localhost:8686/metrics | grep buffer_events

# 5. Temporary: Clear buffer (DESTRUCTIVE)
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- rm -rf /var/lib/vector/*
kubectl delete pod -n $VECTOR_NAMESPACE $POD_NAME  # Let it recreate
```

### Performance Issues / Slow Forwarding

```bash
# 1. Check sink throughput
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- curl -s localhost:8686/metrics | grep -E 'component_sent_events_total|component_sent_bytes_total'

# 2. Check for throttling (429 errors from Azure)
kubectl logs -n $VECTOR_NAMESPACE $POD_NAME | grep -i "429\|throttl\|rate limit"

# 3. Increase concurrency (edit values)
# http.concurrency: 4 → 8 (vector-azure-simple)
# Or adjust batching: http.batchTimeoutSeconds: 1 → 0.5

# 4. Check resource limits
kubectl top pod -n $VECTOR_NAMESPACE

# 5. Scale replicas (for high volume)
# Note: Syslog requires sticky sessions or external LB with consistent hashing
export DEPLOYMENT_NAME=$(kubectl get deployment -n $VECTOR_NAMESPACE -o jsonpath='{.items[0].metadata.name}')
kubectl scale deployment -n $VECTOR_NAMESPACE $DEPLOYMENT_NAME --replicas=2
```

### Parsing Errors (vector-claude)

```bash
# 1. Check for CEF parse errors
kubectl logs -n $VECTOR_NAMESPACE $POD_NAME | grep -i "cef_parse_error"

# 2. View raw messages that failed to parse
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- curl -s localhost:8686/tap/parse_cef -X POST | jq '.parse_status, .cef_parse_error'

# 3. Test CEF parsing locally
# Use test/vector-local.yaml for local Vector instance
export VECTOR_VERSION="0.35.0"
docker run -it --rm -v $(pwd)/workloads/vector-claude/test:/test timberio/vector:$VECTOR_VERSION \
  --config /test/vector-local.yaml < workloads/vector-claude/test/test-messages.txt
```

### ArgoCD Sync Issues

```bash
# 1. Check sync status and errors
argocd app get $VECTOR_APP_NAME

# 2. View diff between Git and cluster
argocd app diff $VECTOR_APP_NAME

# 3. Force hard refresh
argocd app get $VECTOR_APP_NAME --hard-refresh

# 4. Retry failed sync
argocd app sync $VECTOR_APP_NAME --force

# 5. View sync history
argocd app history $VECTOR_APP_NAME

# 6. Rollback to previous revision (get revision number from history first)
export PREVIOUS_REVISION=$(argocd app history $VECTOR_APP_NAME -o json | jq -r '.[1].id')
argocd app rollback $VECTOR_APP_NAME $PREVIOUS_REVISION
```

---

## Monitoring & Metrics

### Prometheus Integration

Vector exposes Prometheus metrics on port 8686:

```bash
# Create ServiceMonitor for Prometheus Operator
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vector-metrics
  namespace: $VECTOR_NAMESPACE
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: $VECTOR_APP_NAME
  endpoints:
    - port: api
      path: /metrics
      interval: 30s
EOF
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
# 1. Backup existing secret (optional)
kubectl get secret $TLS_SECRET_NAME -n $VECTOR_NAMESPACE -o yaml > /tmp/tls-secret-backup.yaml

# 2. Replace existing secret
kubectl delete secret $TLS_SECRET_NAME -n $VECTOR_NAMESPACE
kubectl create secret tls $TLS_SECRET_NAME \
  --cert=/path/to/new-server.crt \
  --key=/path/to/new-server.key \
  -n $VECTOR_NAMESPACE

# 3. Restart pods to load new cert
kubectl rollout restart deployment -n $VECTOR_NAMESPACE
kubectl rollout status deployment -n $VECTOR_NAMESPACE
```

### Backup & Recovery

```bash
# Backup Vector data directory (buffer)
export BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- tar czf - /var/lib/vector > /tmp/vector-backup-${BACKUP_DATE}.tar.gz
echo "Backup saved to: /tmp/vector-backup-${BACKUP_DATE}.tar.gz"

# Backup PVC with Velero (if installed)
velero backup create vector-pvc-backup-${BACKUP_DATE} \
  --include-namespaces $VECTOR_NAMESPACE \
  --include-resources pvc,pv

# Restore from backup
export RESTORE_FILE="/tmp/vector-backup-20260123-120000.tar.gz"
kubectl exec -n $VECTOR_NAMESPACE $POD_NAME -- tar xzf - -C / < $RESTORE_FILE
kubectl delete pod -n $VECTOR_NAMESPACE $POD_NAME  # Restart to apply
```

---

## Direct Helm Deployment (Non-ArgoCD)

For testing or non-GitOps environments:

```bash
# Set release name
export HELM_RELEASE="vector-${VECTOR_APP_NAME##*-}"  # e.g., vector-simple, vector-claude

# Install
helm install $HELM_RELEASE ./workloads/$VECTOR_APP_NAME -n $VECTOR_NAMESPACE \
  --set azure.dcrUri="$DCR_URI" \
  --set persistence.storageClassName="$STORAGE_CLASS" \
  --create-namespace

# Upgrade with custom values
helm upgrade $HELM_RELEASE ./workloads/$VECTOR_APP_NAME -n $VECTOR_NAMESPACE \
  -f /tmp/vector-prod-values.yaml

# Show current values
helm get values $HELM_RELEASE -n $VECTOR_NAMESPACE

# Rollback to previous release
helm rollback $HELM_RELEASE -n $VECTOR_NAMESPACE

# List releases
helm list -n $VECTOR_NAMESPACE

# Uninstall
helm uninstall $HELM_RELEASE -n $VECTOR_NAMESPACE
```

---

## ArgoCD Best Practices & Drift Prevention

**Follow these rules to ensure your cluster stays in sync with Git and avoid configuration drift:**

### 1. Git is the Source of Truth
- **Never** apply resources directly with `kubectl apply`, `kubectl edit`, or `helm install/upgrade`.
- All changes must go through Git and be reconciled by ArgoCD.

### 2. Automated Sync, Prune, and Self-Heal
- Use `syncPolicy.automated.prune: true` and `selfHeal: true` in all ArgoCD Application specs:

```yaml
syncPolicy:
  automated:
    prune: true        # Delete resources not in Git
    selfHeal: true     # Revert manual changes in cluster
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

- This ensures ArgoCD will:
  - Automatically sync changes from Git
  - Delete orphaned resources
  - Overwrite any manual changes in the cluster

### 3. Detecting and Resolving Drift
- Use `argocd app diff <app>` to see differences between Git and cluster
- Use `argocd app sync <app> --force` to force reconciliation
- Use `argocd app history <app>` and `argocd app rollback <app> <revision>` to revert to a previous state
- If you must make a manual change (emergency only), document it and immediately restore desired state in Git

### 4. Sync Waves and Dependency Ordering
- Use `argocd.argoproj.io/sync-wave` annotations to control resource apply order (e.g., namespaces before apps)
- Example:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

### 5. Ignore Differences for Volatile Fields
- Use `ignoreDifferences` in Application spec to avoid false drift on fields like webhook caBundle, status, etc.
- Example:
```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jsonPointers:
      - /webhooks/0/clientConfig/caBundle
```

### 6. Health Checks and Monitoring
- Use ArgoCD's health status and `argocd app get <app>` to monitor sync and health
- Integrate with Prometheus/Grafana for alerting on OutOfSync or Degraded status

### 7. Policy Reminders
- All configuration must be in `values.yaml` or manifests in Git
- No secrets in Git: use External Secrets Operator and Azure Key Vault
- Pin all chart and image versions
- Document all manual interventions in `logs/commands/` and `logs/problems/`

### 8. Recovery and Rollback
- Use `git revert` and ArgoCD sync to roll back changes
- If ArgoCD is blocked, document the incident and restore desired state via PR

**Reference:** See AGENTS.md in the repo for the full GitOps operating manual and critical rules.

---
