# Vector Azure Simple

Helm chart for deploying Vector with syslog TLS ingestion and single Azure Log Analytics destination.

## Features

- Syslog over TLS on port 6514
- Single Azure Log Analytics DCR endpoint
- Disk buffering for reliability
- Kubernetes-native secrets (no external secrets operator required)
- Automatic severity mapping for Azure

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Azure Log Analytics workspace with DCR configured
- TLS certificate for syslog ingestion

## Quick Start

### 1. Create Secrets

```bash
# TLS certificate
kubectl create secret tls vector-tls \
  --cert=server.crt \
  --key=server.key \
  -n logging

# Azure token (short-lived, see notes below)
TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)
kubectl create secret generic azure-log-analytics \
  --from-literal=token="$TOKEN" \
  -n logging
```

### 2. Configure Values

```yaml
# values-prod.yaml
azure:
  tokenSecretName: "azure-log-analytics"
  tokenSecretKey: "token"
  dcrUri: "https://your-dce.eastus-1.ingest.monitor.azure.com/dataCollectionRules/dcr-xxx/streams/Custom-Syslog_CL?api-version=2023-01-01"

service:
  type: LoadBalancer
```

### 3. Install

```bash
helm install vector-azure ./vector-azure-simple -n logging -f values-prod.yaml
```

## Azure Token Management

Azure bearer tokens expire (typically 1 hour). For production:

**Option 1: Azure Workload Identity** (Recommended)
- Configure workload identity on AKS
- Vector can use managed identity

**Option 2: Token Refresh CronJob**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: refresh-azure-token
spec:
  schedule: "*/45 * * * *"  # Every 45 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: refresh
            image: mcr.microsoft.com/azure-cli
            command:
            - /bin/sh
            - -c
            - |
              TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)
              kubectl create secret generic azure-log-analytics --from-literal=token="$TOKEN" --dry-run=client -o yaml | kubectl apply -f -
          restartPolicy: OnFailure
```

**Option 3: External Secrets Operator**
- Use ESO with Azure Key Vault
- Automatic token rotation

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `azure.dcrUri` | Azure DCR endpoint | (required) |
| `azure.tokenSecretName` | K8s secret name | `azure-log-analytics` |
| `tls.secretName` | TLS secret name | `vector-tls` |
| `buffer.maxSizeBytes` | Disk buffer size | `10737418240` (10GB) |
| `persistence.size` | PVC size | `20Gi` |

## Troubleshooting

### Events not appearing in Azure

1. Check token validity:
```bash
kubectl get secret azure-log-analytics -o jsonpath='{.data.token}' | base64 -d | cut -d. -f2 | base64 -d 2>/dev/null | jq .exp
```

2. Verify DCR URI format:
```
https://<DCE>.ingest.monitor.azure.com/dataCollectionRules/<DCR-ID>/streams/<Stream>?api-version=2023-01-01
```

3. Check Vector logs:
```bash
kubectl logs -l app.kubernetes.io/name=vector-azure-simple --tail=100
```

### Buffer filling up

If disk buffer grows continuously:
- Azure endpoint may be unreachable
- Token may be expired
- DCR may be misconfigured

Check with:
```bash
kubectl exec deploy/vector-azure-simple -- du -sh /var/lib/vector/
```
