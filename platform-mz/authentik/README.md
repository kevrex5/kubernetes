# Authentik - Identity Provider (SSO/IdP)

Authentik provides Single Sign-On (SSO) and identity management for the platform.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     rex5-cc-mz-k8s-authentik                    │
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │   Server    │◄───│   Traefik   │◄───│  External Traffic   │ │
│  │  (replicas  │    │  (Gateway)  │    │  (auth.rex5.ca)     │ │
│  │    = 2)     │    └─────────────┘    └─────────────────────┘ │
│  └──────┬──────┘                                                │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────┐                                                │
│  │   Worker    │                                                │
│  │  (replicas  │                                                │
│  │    = 2)     │                                                │
│  └──────┬──────┘                                                │
│         │                                                       │
│    ┌────┴────┐                                                  │
│    ▼         ▼                                                  │
│ ┌──────┐  ┌───────────┐                                         │
│ │Redis │  │PostgreSQL │                                         │
│ │(1Gi) │  │  (8Gi)    │                                         │
│ └──────┘  └───────────┘                                         │
└─────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Replicas | Purpose | Storage |
|-----------|----------|---------|---------|
| Server | 2 | Web UI, API, OAuth/OIDC endpoints | - |
| Worker | 2 | Background tasks, email, webhooks | - |
| PostgreSQL | 1 | Primary database | 8Gi (managed-csi-premium) |
| Redis | 1 | Cache, sessions, task queue | 1Gi (managed-csi-premium) |

## Security Features

### Pod Security Admission
- Namespace enforces `baseline` PSA level (required for platform components)
- Defined in `platform/namespaces/authentik.yaml`

### Network Policies
All network traffic is explicitly controlled via `networkpolicies.yaml`:

| From | To | Ports | Purpose |
|------|-----|-------|---------|
| Traefik | Server | 9000, 9443 | HTTP/HTTPS ingress |
| Monitoring | Server/Worker | 9300 | Prometheus metrics |
| Server/Worker | PostgreSQL | 5432 | Database |
| Server/Worker | Redis | 6379 | Cache/sessions |
| Server/Worker | Internet | 443 | Azure AD, webhooks |
| Worker | Internet | 587, 465 | SMTP (email) |

### High Availability
- Server: 2 replicas with PodDisruptionBudget (minAvailable: 1)
- Worker: 2 replicas with PodDisruptionBudget (minAvailable: 1)
- PostgreSQL/Redis: PDBs prevent accidental deletion

### Spot Instance Strategy
| Component | Spot Toleration | Reason |
|-----------|-----------------|--------|
| Server | ✅ Yes | Stateless, HA replicas handle eviction |
| Worker | ✅ Yes | Stateless, HA replicas handle eviction |
| PostgreSQL | ❌ No | Data integrity - must not be evicted mid-transaction |
| Redis | ✅ Yes | Persistence enabled, data survives restart |

## Secrets Management

Secrets are managed via External Secrets Operator from Azure Key Vault.

### Required Key Vault Secrets

| Key Vault Secret Name | Environment Variable | Description |
|-----------------------|---------------------|-------------|
| `authentik-secret-key` | `AUTHENTIK_SECRET_KEY` | Django secret key |
| `authentik-postgres-password` | `AUTHENTIK_POSTGRESQL__PASSWORD` | PostgreSQL password |
| `authentik-azure-client-id` | `AUTHENTIK_AZURE_CLIENT_ID` | Azure AD app client ID |
| `authentik-azure-client-secret` | `AUTHENTIK_AZURE_CLIENT_SECRET` | Azure AD app client secret |
| `authentik-azure-tenant-id` | `AUTHENTIK_AZURE_TENANT_ID` | Azure AD tenant ID |
| `grafana-oidc-client-id` | `GRAFANA_OIDC_CLIENT_ID` | Grafana OIDC client ID |
| `grafana-oidc-client-secret` | `GRAFANA_OIDC_CLIENT_SECRET` | Grafana OIDC client secret |
| `espocrm-oidc-client-id` | `ESPOCRM_OIDC_CLIENT_ID` | EspoCRM OIDC client ID |
| `espocrm-oidc-client-secret` | `ESPOCRM_OIDC_CLIENT_SECRET` | EspoCRM OIDC client secret |

### Creating Secrets in Key Vault

```bash
# Generate random secrets
AUTHENTIK_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -base64 24)
GRAFANA_CLIENT_ID=$(uuidgen)
GRAFANA_CLIENT_SECRET=$(openssl rand -base64 32)
ESPOCRM_CLIENT_ID=$(uuidgen)
ESPOCRM_CLIENT_SECRET=$(openssl rand -base64 32)

# Store in Key Vault
az keyvault secret set --vault-name <KEYVAULT_NAME> --name authentik-secret-key --value "$AUTHENTIK_SECRET"
az keyvault secret set --vault-name <KEYVAULT_NAME> --name authentik-postgres-password --value "$POSTGRES_PASSWORD"
az keyvault secret set --vault-name <KEYVAULT_NAME> --name grafana-oidc-client-id --value "$GRAFANA_CLIENT_ID"
az keyvault secret set --vault-name <KEYVAULT_NAME> --name grafana-oidc-client-secret --value "$GRAFANA_CLIENT_SECRET"
az keyvault secret set --vault-name <KEYVAULT_NAME> --name espocrm-oidc-client-id --value "$ESPOCRM_CLIENT_ID"
az keyvault secret set --vault-name <KEYVAULT_NAME> --name espocrm-oidc-client-secret --value "$ESPOCRM_CLIENT_SECRET"
```

## Blueprints

Authentik configuration is managed as code via blueprints:

| Blueprint | Purpose |
|-----------|---------|
| `blueprint-azure-ad` | Azure AD federation (OIDC source) |
| `blueprint-groups-users` | Default groups (rex5-it, rex5-sales) |
| `blueprint-grafana` | Grafana OIDC provider |
| `blueprint-espocrm` | EspoCRM OIDC provider |
| `blueprint-app-azure-mz` | Azure MZ portal link |
| `blueprint-app-azure-cz` | Azure CZ portal link |

## Routing

Traffic flows via Gateway API:

```
Internet → Traefik Gateway → HTTPRoute → authentik-server:9000
           (websecure)       (auth.rex5.ca)
```

HTTP requests are automatically redirected to HTTPS via a separate HTTPRoute.

## Files

| File | Purpose |
|------|---------|
| `values.yaml` | Helm chart configuration |
| `httproute.yaml` | Gateway API routing |
| `externalsecret.yaml` | Key Vault secret references |
| `networkpolicies.yaml` | Network security rules |
| `pdb.yaml` | Pod disruption budgets |
| `kustomization.yaml` | Kustomize resource list |
| `blueprints/*.yaml` | Authentik configuration as code |

## Monitoring

Prometheus metrics are exposed on port 9300:
- Server pods: `prometheus.io/scrape: "true"`, port 9300
- Worker pods: `prometheus.io/scrape: "true"`, port 9300

## Maintenance

### Viewing Logs
```bash
# Server logs
kubectl logs -n rex5-cc-mz-k8s-authentik -l app.kubernetes.io/component=server -f

# Worker logs
kubectl logs -n rex5-cc-mz-k8s-authentik -l app.kubernetes.io/component=worker -f

# PostgreSQL logs
kubectl logs -n rex5-cc-mz-k8s-authentik -l app.kubernetes.io/name=postgresql -f
```

### Database Backup (Manual)
```bash
# Create backup
kubectl exec -n rex5-cc-mz-k8s-authentik \
  $(kubectl get pod -n rex5-cc-mz-k8s-authentik -l app.kubernetes.io/name=postgresql -o name) \
  -- pg_dump -U authentik authentik > authentik-backup-$(date +%Y%m%d).sql
```

### Troubleshooting

1. **Pods not starting**: Check ExternalSecret sync status
   ```bash
   kubectl get externalsecret -n rex5-cc-mz-k8s-authentik
   ```

2. **Network connectivity**: Verify NetworkPolicies allow required traffic
   ```bash
   kubectl get networkpolicy -n rex5-cc-mz-k8s-authentik
   ```

3. **Blueprint errors**: Check server logs for blueprint instantiation
   ```bash
   kubectl logs -n rex5-cc-mz-k8s-authentik -l app.kubernetes.io/component=server | grep -i blueprint
   ```

## Related Documentation

- [Authentik Official Docs](https://goauthentik.io/docs/)
- [Helm Chart Values](https://github.com/goauthentik/helm/tree/main/charts/authentik)
- [Blueprint Reference](https://goauthentik.io/developer-docs/blueprints/)
