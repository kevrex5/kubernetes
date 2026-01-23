# Vector Syslog Helm Chart

Production-quality Helm chart for deploying Timber.io Vector as a syslog TLS ingestion service with CEF parsing and Azure Log Ingestion forwarding.

## Features

- **Syslog over TLS**: Secure syslog ingestion on port 6514
- **CEF Parsing**: Automatic detection and forwarding of CEF-formatted events
- **Load Distribution**: Hash-based 50/50 splitting to two Azure DCR endpoints
- **Reliability**: Disk-buffered forwarding with automatic retries
- **Production Ready**: Proper security contexts, health checks, and resource limits

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Azure Data Collection Rules (DCR) configured
- TLS certificate for syslog ingestion
- Azure DCR ingestion token

## Installation

### 1. Create Required Secrets

```bash
# TLS certificate for syslog ingestion
kubectl create secret tls vector-syslog-tls \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n <namespace>

# Azure DCR ingestion token
kubectl create secret generic azure-ingest-token \
  --from-literal=token='YOUR_BEARER_TOKEN' \
  -n <namespace>
```

### 2. Configure Values

Create a `custom-values.yaml` file:

```yaml
dcr:
  dcr1:
    uri: "https://your-dce.ingest.monitor.azure.com/dataCollectionRules/dcr-xxx/streams/Custom-YourTable_CL?api-version=2023-01-01"
    name: "dcr-prod-1"
  dcr2:
    uri: "https://your-dce.ingest.monitor.azure.com/dataCollectionRules/dcr-yyy/streams/Custom-YourTable_CL?api-version=2023-01-01"
    name: "dcr-prod-2"

service:
  type: LoadBalancer  # or ClusterIP/NodePort

resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

### 3. Install the Chart

```bash
helm install vector-syslog ./vector-claude \
  -n <namespace> \
  -f custom-values.yaml
```

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Vector image repository | `timberio/vector` |
| `image.tag` | Vector image tag | `0.35.0` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Syslog ingestion port | `6514` |
| `tls.secretName` | TLS certificate secret name | `vector-syslog-tls` |
| `env.ingestTokenSecretName` | Azure token secret name | `azure-ingest-token` |
| `dcr.dcr1.uri` | First Azure DCR endpoint | (required) |
| `dcr.dcr2.uri` | Second Azure DCR endpoint | (required) |
| `persistence.size` | Disk buffer size | `50Gi` |
| `buffer.maxSizeBytes` | Maximum buffer size | `21474836480` (20GB) |
| `hashSplit.keyFields` | Fields for hash computation | `[.host, .appname, .message]` |

See `values.yaml` for complete configuration options.

## Testing

### Test Syslog Ingestion

```bash
# Port-forward the service
kubectl port-forward -n <namespace> svc/vector-syslog 6514:6514

# Send a CEF message
echo '<14>1 2024-01-15T10:30:00Z myhost myapp 1234 - - CEF:0|Security|Firewall|1.0|100|Connection Denied|5| src=10.0.0.1 dst=192.168.1.1' | \
  openssl s_client -connect localhost:6514 -quiet -no_ign_eof
```

### Check Health

```bash
# Port-forward the API
kubectl port-forward -n <namespace> svc/vector-syslog 8686:8686

# Check health endpoint
curl http://localhost:8686/health
```

### View Logs

```bash
kubectl logs -n <namespace> -l app.kubernetes.io/name=vector-syslog -f
```

## Architecture

```
Syslog TLS (6514) -> Vector -> Parse -> Filter CEF -> Hash Split
                                                        |-- Bucket 0 -> Azure DCR 1
                                                        |-- Bucket 1 -> Azure DCR 2
```

**Hash Splitting**: Events are distributed based on a stable hash of host, appname, and message fields, ensuring consistent routing for the same source.

## Troubleshooting

### Pods not starting

Check events:
```bash
kubectl describe pod -n <namespace> -l app.kubernetes.io/name=vector-syslog
```

### TLS connection issues

Verify certificate:
```bash
kubectl get secret vector-syslog-tls -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

### No events reaching Azure

1. Check Vector logs for errors
2. Verify DCR URIs are correct
3. Ensure ingestion token is valid
4. Check network policies allow egress to Azure

### Buffer filling up

Monitor disk usage:
```bash
kubectl exec -n <namespace> <pod-name> -- df -h /var/lib/vector
```

## Upgrading

```bash
helm upgrade vector-syslog ./vector-claude \
  -n <namespace> \
  -f custom-values.yaml
```

## Uninstalling

```bash
helm uninstall vector-syslog -n <namespace>

# Optionally delete PVC
kubectl delete pvc vector-syslog-data -n <namespace>
```

## License

Apache 2.0
