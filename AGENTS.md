# AGENTS.md — Kubernetes Platform (AKS) GitOps Operating Manual

This repo is the **source of truth** for our Azure Kubernetes (AKS) platform and workloads.
Humans and AI agents must follow this guide to make changes **securely**, **repeatably**, and **without drift**.

---

## Non-negotiables

1) **Git is the source of truth.**  
   - No "clickops" or manual changes in the cluster except break-glass incidents.
   - If a manual change is unavoidable, it must be recorded in:
     - `logs/problems/` (incident entry), and
     - a follow-up PR must restore desired state in Git.

2) **ArgoCD reconciles everything.**  
   - Anything deployed must be represented as Helm releases managed by ArgoCD.
   - **NEVER run `kubectl apply`, `helm install`, or `helm upgrade` directly on the cluster.**
   - All changes go through Git → ArgoCD sync.

3) **All configuration changes go in values.yaml.**  
   - Update Helm chart values in Git (`platform/<component>/values.yaml` or `apps/<app>/values.yaml`)
   - Update additional resources (HTTPRoutes, ExternalSecrets, etc.) in their respective directories
   - Commit → Push → Let ArgoCD sync
   - **DO NOT** manually apply manifests or run Helm commands

4) **No secrets in Git.**  
   - Secrets come from Azure Key Vault via External Secrets Operator (ESO).
   - Git contains only references (ExternalSecret objects / SecretStore config).

5) **Pin versions.**  
   - Helm chart versions are pinned.
   - ArgoCD tracks a pinned Git revision for production unless explicitly approved otherwise.

6) **Log work so we don't loop.**  
   - Commands, prompts, failures, and investigations are logged every session.

---

## 🚨 CRITICAL GitOps Rules 🚨

**THESE RULES MUST ALWAYS BE FOLLOWED. NO EXCEPTIONS.**

### ✅ DO THIS (The GitOps Way)
1. **Update values.yaml** in Git for any Helm chart configuration change
2. **Create/update resource files** (Gateway, HTTPRoute, ExternalSecret) in their respective directories
3. **Commit and push** changes to Git
4. **Let ArgoCD sync** automatically (or manually sync via ArgoCD UI/CLI)
5. **Verify via ArgoCD** that the application is Healthy and Synced

### ❌ NEVER DO THIS (Anti-Patterns)
1. **DO NOT run `kubectl apply -f <file>`** — This creates drift between Git and cluster
2. **DO NOT run `kubectl edit <resource>`** — Changes will be overwritten by ArgoCD
3. **DO NOT run `kubectl create <resource>`** — Must be defined in Git first
4. **DO NOT run `helm install <chart>`** — Only ArgoCD installs Helm charts
5. **DO NOT run `helm upgrade <release>`** — Only ArgoCD upgrades releases
6. **DO NOT manually modify cluster resources** — Git is the source of truth

### 🔧 How to Make Changes (Step by Step)

**Example: Update Traefik configuration**
```bash
# 1. Create branch
git checkout -b platform/update-traefik-config

# 2. Edit the values file
vim platform/traefik/values.yaml

# 3. Commit changes
git add platform/traefik/values.yaml
git commit -m "platform(traefik): enable prometheus metrics"

# 4. Push to Git
git push origin platform/update-traefik-config

# 5. Wait for ArgoCD to sync (or manually trigger)
argocd app sync platform-traefik

# 6. Verify
argocd app get platform-traefik
```

**Example: Add a new Gateway resource**
```bash
# 1. Create branch
git checkout -b platform/add-shared-gateway

# 2. Create the resource file
vim platform/traefik/gateway.yaml

# 3. Update kustomization to include it
vim platform/traefik/kustomization.yaml

# 4. Commit changes
git add platform/traefik/gateway.yaml platform/traefik/kustomization.yaml
git commit -m "platform(traefik): add shared gateway with https listener"

# 5. Push and let ArgoCD sync
git push origin platform/add-shared-gateway
```

### 🆘 Break-Glass Exceptions
Manual cluster changes are ONLY allowed during:
- Initial cluster bootstrap (before ArgoCD is installed)
- Active production incidents where Git workflow is too slow
- Testing/validation in development environments (with immediate Git sync)

**If you make a manual change:**
1. Document it in `logs/problems/PROB-YYYYMMDD-###.md`
2. Immediately create a PR to sync Git with the change
3. Apply the PR so ArgoCD owns the resource going forward

---

## Repository layout

Recommended structure (this repo follows it):

```
argocd/
  projects/               # Argo AppProjects (platform, apps)
  apps/                   # Root applications (platform + apps)
  install/                # ArgoCD installation (Helm values)

platform/
  namespaces/             # Namespace manifests + Pod Security labels
  policies/               # NetworkPolicies + baseline policies
  traefik/                # Helm values + Gateway/GatewayClass
  cert-manager/           # Helm values + ClusterIssuers
  external-secrets/       # Helm values + ClusterSecretStores
  authentik/              # SSO/IdP (Helm values + blueprints)
  monitoring/             # Prometheus, Grafana, Alertmanager
  shared/                 # Shared resources (wildcard certs, storage classes)

apps/
  <app-name>/             # One folder per app (Helm values + HTTPRoute)

environments/
  prod/                   # Production environment configuration
    config.yaml           # Centralized environment values (SINGLE SOURCE OF TRUTH)
    platform/             # Environment-specific platform overrides (if needed)
    apps/                 # Environment-specific app overrides (if needed)

scripts/
  apply-config.sh         # Script to apply environment config to manifests

docs/

logs/
  commands/
  prompts/
  problems/
  commits/
```

---

## Environment Configuration (Centralized Values)

All environment-specific values (domains, Azure resource IDs, managed identities, etc.) are defined in a **single configuration file**:

```
environments/<env>/config.yaml
```

### Why centralized configuration?

1. **Single source of truth** — Change a value once, it applies everywhere
2. **Environment portability** — Easy to add staging/dev by copying config.yaml
3. **Clear audit trail** — Git history shows exactly when/why config changed
4. **No scattered placeholders** — All environment values in one place

### Configuration file structure

```yaml
# environments/prod/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: environment-config
  annotations:
    config.kubernetes.io/local-config: "true"  # Not applied to cluster
data:
  DOMAIN: "rex5.ca"
  AZURE_SUBSCRIPTION_ID: "..."
  AZURE_TENANT_ID: "..."
  KEYVAULT_NAME: "..."
  # ... all environment values
```

### How to use

1. **Edit config** — Update `environments/prod/config.yaml`
2. **Apply to manifests** — Run `./scripts/apply-config.sh prod`
3. **Commit & push** — ArgoCD syncs the changes

### Adding a new environment

```bash
cp -r environments/prod environments/staging
# Edit environments/staging/config.yaml with staging values
./scripts/apply-config.sh staging
```

---

## Cluster model (one cluster)

- Single AKS cluster.
- Namespaces separate **platform** vs **apps** using `rex5-cc-mz-prod-<component>` naming convention.
- Traefik is the **only** public entrypoint (Service type LoadBalancer).
- Apps use **Kubernetes Gateway API** (`HTTPRoute`, `TCPRoute`, `GRPCRoute`).
- A shared `Gateway` resource in `rex5-cc-mz-prod-traefik` namespace handles all routing.
- TLS is issued by **cert-manager** using **Azure DNS DNS-01**.
- Wildcard certificate (`*.rex5.ca`) is stored in Azure Key Vault and distributed via ESO.
- Secrets are delivered via **External Secrets Operator** from **Azure Key Vault**.
- **Authentik** provides SSO/OIDC for internal applications.

---

## Security baseline (must remain true)

### Namespace / Pod Security
- Application namespaces: Pod Security Admission **restricted**
- Platform namespaces: Pod Security Admission **baseline**

Required PSA labels on all namespaces:
```yaml
labels:
  pod-security.kubernetes.io/enforce: restricted  # or baseline for platform
  pod-security.kubernetes.io/audit: restricted
  pod-security.kubernetes.io/warn: restricted
```

Namespace manifests must be present in `platform/namespaces/*`.

### Networking
- App namespaces have baseline NetworkPolicies:
  - Default deny ingress
  - Allow ingress from Traefik namespace
  - Allow DNS egress
  - Any additional egress must be explicit per app/team

### Identity
- Prefer Azure Workload Identity for controllers that access Azure APIs (DNS, Key Vault).
- Avoid long-lived secrets for Azure auth where feasible.

---

## Tooling prerequisites (local machine)

Required:
- `az` (Azure CLI)
- `kubectl`
- `helm`
- `argocd` CLI (optional but useful)
- `git`

Recommended:
- `kubeconform` (manifest validation)
- `helm-diff` (optional)

---

## Golden path workflows

### A) Bootstrap (fresh cluster)
Order matters (CRDs + dependencies):

1. Connect/auth:
   - `az login`
   - `az account set --subscription <SUBSCRIPTION_ID>`
   - `az aks get-credentials -g <AKS_RG> -n <AKS_NAME> --overwrite-existing`
   - Confirm context: `kubectl config current-context`

2. Install ArgoCD (manual once, then GitOps takes over):
   - Create namespace:
     - `kubectl create namespace rex5-cc-mz-prod-argocd`
   - Install ArgoCD via Helm:
     - `helm repo add argo https://argoproj.github.io/argo-helm`
     - `helm install argocd argo/argo-cd -n rex5-cc-mz-prod-argocd -f argocd/install/values.yaml`
   - Configure SSH credentials for Git access (see argocd/install/README.md)

3. Apply ArgoCD AppProjects and root app (app-of-apps):
   - `kubectl apply -f argocd/projects/platform.yaml`
   - `kubectl apply -f argocd/projects/apps.yaml`
   - `kubectl apply -f argocd/apps/root.yaml`

4. ArgoCD sync brings up (via sync waves):
   - Wave -1: namespaces
   - Wave 0: shared resources
   - Wave 1: cert-manager (v1.17.1)
   - Wave 2: external-secrets (v0.17.0)
   - Wave 3: traefik
   - Wave 4+: authentik, monitoring, app workloads

Record bootstrap commands and outcomes in:
- `logs/commands/YYYY-MM-DD.md`

### B) Day-to-day change workflow (every PR)

**CRITICAL: All changes must go through Git → ArgoCD. Never apply resources directly to the cluster.**

1. Create a branch:
   - `git checkout -b <type>/<short-change>`

2. Make changes in Git:
   - **UPDATE values.yaml** for Helm chart configuration changes
   - **UPDATE or CREATE** additional resource files (Gateway, HTTPRoute, ExternalSecret, etc.)
   - **COMMIT to Git** — do not apply directly to cluster

3. Validate locally (minimum):
   - Helm render check:
     - `helm template <release-name> <chart-path> -f <values.yaml> > /tmp/rendered.yaml`
   - Kubernetes schema check (recommended):
     - `kubeconform -strict -ignore-missing-schemas /tmp/rendered.yaml`

4. Commit (see commit rules below).

5. Open PR with:
   - what changed
   - validation output
   - rollback plan
   - links to relevant Argo apps

6. Merge.

7. Confirm ArgoCD health:
   - `argocd app get <app>` or via UI
   - Record final status in `logs/commits/YYYY-MM-DD.md`

### C) Rollback workflow
- Prefer "revert commit":
  - `git revert <sha>`
  - merge PR
  - ArgoCD reconciles rollback

If ArgoCD is blocked (rare):
- Record a break-glass incident in `logs/problems/`
- Stabilize
- Restore desired state via PR

---

## Versioning rules (Helm + ArgoCD)

1) **Pin Helm chart versions.**  
No floating latest tags for platform dependencies.

**Current versions:**
- cert-manager: v1.17.1
- external-secrets: v0.17.0 (supports v1 API)
- traefik: v3.2.0

2) **Pin container image tags** for critical workloads.  
Prefer semver tags. Use digests for high-risk components if needed.

3) **ArgoCD revisions**
- Production should track a tagged release or a protected branch strategy.
- If tracking `main` for prod, it must be explicitly documented in an ADR.

---

## Common Pitfalls & Solutions

### AppProject Configuration
**Issue**: Applications fail with "not permitted in project" errors  
**Solution**: Ensure AppProject includes:
- Both HTTPS and SSH Git URLs in `sourceRepos`
- `default` namespace in destinations (for namespace creation)
- RBAC cluster resources in `clusterResourceWhitelist` (ClusterRole, ClusterRoleBinding)

### Kustomization Files
**Issue**: ArgoCD tries to apply kustomization.yaml as CRD  
**Solution**: Exclude from directory sources: `exclude: '{values.yaml,kustomization.yaml}'`

### External Secrets API Version
**Issue**: Pods crash with "no matches for kind ExternalSecret in version external-secrets.io/v1beta1"  
**Solution**: Use external-secrets v0.17.0+ which supports v1 API

### cert-manager Leader Election
**Issue**: RBAC errors for resources in wrong namespace  
**Solution**: Set `global.leaderElection.namespace` to match deployment namespace (rex5-cc-mz-prod-cert-manager)

### Git Authentication
**Issue**: ArgoCD can't clone repository via SSH  
**Solution**: 
- Store SSH private key in Key Vault
- Create secret with labels: `argocd.argoproj.io/secret-type=repository`
- Include: `type=git`, `url=git@github.com:<org>/<repo>.git`, `insecure=true`, `sshPrivateKey`
- Restart repo-server pods after secret updates

---

## ArgoCD conventions

### AppProjects
- Platform apps belong to a platform AppProject.
- Business apps belong to an apps AppProject.
- Projects restrict:
  - allowed destinations (cluster/namespaces)
  - allowed source repos (must include both HTTPS and SSH Git URLs)
  - cluster resource permissions

**Critical AppProject configurations**:
- Include `default` namespace in destinations for namespace creation
- Add RBAC cluster resources to `clusterResourceWhitelist`:
  - `rbac.authorization.k8s.io/ClusterRole`
  - `rbac.authorization.k8s.io/ClusterRoleBinding`
- Support both Git URL formats in `sourceRepos`:
  - `https://github.com/<org>/<repo>.git`
  - `git@github.com:<org>/<repo>.git`

### Root apps
- `argocd/apps/root.yaml` — Single root Application that creates:
  - `platform-apps` — All platform infrastructure Applications
  - `workload-apps` — ApplicationSet for auto-discovering apps

### Application naming
- Platform: `platform-<component>` (e.g., `platform-traefik`, `platform-cert-manager`)
- Workloads: Discovered from `apps/<appname>/` directories

### Multi-source Applications
- Platform apps use multi-source pattern:
  1. Helm chart from upstream repo
  2. Git values file reference (`$values/platform/<component>/values.yaml`)
  3. Additional manifests from Git (ClusterIssuers, HTTPRoutes, etc.)
- **Important**: Exclude `kustomization.yaml` from directory sources to prevent CRD conflicts

---

## Platform standards

### Traefik (Gateway API)
- Use **Kubernetes Gateway API** for routing (not IngressRoute CRDs).
- Resources:
  - `GatewayClass` — defines Traefik as the controller
  - `Gateway` — shared gateway in `rex5-cc-mz-prod-traefik` namespace
  - `HTTPRoute` / `TCPRoute` — per-app routing in app namespaces
- Gateway listeners:
  - `http` (port 80) — redirects to HTTPS
  - `https` (port 443) — TLS termination with wildcard cert
  - Custom TCP ports as needed (e.g., syslog on 514/6514)
- Route namespaces are controlled via `allowedRoutes.namespaces.selector`

### cert-manager (Azure DNS DNS-01)
- Maintain 2 ClusterIssuers:
  - `letsencrypt-staging` (testing)
  - `letsencrypt-prod` (real)
- Wildcard certificate (`*.rex5.ca`) issued once, stored in Key Vault via PushSecret
- Apps retrieve the wildcard cert via ExternalSecret (no per-app cert issuance)

### External Secrets Operator (Azure Key Vault)
- ClusterSecretStores for each Key Vault:
  - `azure-keyvault-store` — main platform vault
  - `azure-keyvault-customerzone-store` — customer-zone vault (if applicable)
- Uses Azure Workload Identity (no static credentials)
- ExternalSecret resources live with the app in `apps/<app>/`

### Authentik (SSO/IdP)
- Provides OIDC authentication for internal applications
- Blueprints define applications and providers as code
- Apps configure OIDC via ExternalSecret for client credentials

---

## Logging requirements (MANDATORY)

All work sessions must update logs. This is how we avoid retry loops and preserve decisions.

### 1) Command log (every session)
Create/update:
- `logs/commands/YYYY-MM-DD.md`

Minimum sections:
- ✅ Commands that worked
- ❌ Commands that failed
- 🚫 DO NOT RETRY (commands that are known-bad)

Template:

```md
# Commands — YYYY-MM-DD

## Context
- Goal:
- Branch/PR:
- Cluster/Namespace:

## ✅ Worked
- `command`
  - Expected:
  - Result:

## ❌ Failed
- `command`
  - Error:
  - Why it failed:
  - Replacement approach:

## 🚫 DO NOT RETRY
- `command`
  - Reason:
  - What to do instead:
```

### 2) Prompt log (when using AI assistance)
Create/update:
- `logs/prompts/YYYY-MM-DD.md`

Template:

```md
# Prompts — YYYY-MM-DD

## Goal
## Prompt(s)
## Outputs used
## Outputs rejected (and why)
## Follow-ups / next steps
```

### 3) Problem log (when debugging takes > 15 minutes OR impacts availability/security)
Create:
- `logs/problems/PROB-YYYYMMDD-###-short-title.md`

Template:

```md
# PROB-YYYYMMDD-### — <title>

## Summary
## Impact
## Timeline (with timestamps)
## Signals / Symptoms
## Hypotheses
## Tests performed (commands + results)
## Root cause
## Fix applied
## Verification
## Prevention (policy, automation, documentation)
## Links (PRs, Argo apps, dashboards)
```

### 4) Commit log (for merges/releases)
Create/update:
- `logs/commits/YYYY-MM-DD.md`

Template:

```md
# Commits — YYYY-MM-DD

- PR:
- Change summary:
- Validation evidence:
- Argo apps impacted:
- Rollback plan:
- Final Argo status:
```

---

## Commit message format

Use:

```
platform(<component>): <change>

apps(<app>): <change>

policies: <change>

docs: <change>

logs: <change>
```

Examples:

```
platform(traefik): enable ingressroute dashboard behind auth middleware

platform(cert-manager): add letsencrypt-prod clusterissuer (azuredns dns01)

apps(portal): add ingressroute + external secret refs
```

---

## PR checklist (required)

Every PR must include:

- [ ] What changed + why
- [ ] Validation output (copy/paste)
  - `helm template ...`
  - `kubeconform ...` (if available)
- [ ] Argo apps impacted
- [ ] Rollback plan (revert commit + sync)
- [ ] Any new "DO NOT RETRY" command(s) added to command log if applicable

---

## Stop conditions (open a problem log and stop iterating)

Stop and create `logs/problems/...` if:

- You hit the same error twice
- You're changing cluster-wide security, identity, or ingress fundamentals
- cert issuance fails in a non-obvious way
- External Secrets can't read from Key Vault
- Anything suggests drift between cluster and Git

---

## Operational runbook shortcuts

### Quick triage (Argo)
```bash
argocd app list
argocd app get <app>
argocd app diff <app>
argocd app sync <app>
```

### Quick triage (Kubernetes)
```bash
kubectl get pods -A
kubectl get events -A --sort-by=.metadata.creationTimestamp
kubectl describe <resource> <name> -n <ns>
kubectl logs <pod> -n <ns> --tail=200
```

### Controllers (common namespaces)
- ArgoCD: `rex5-cc-mz-prod-argocd`
- Traefik: `rex5-cc-mz-prod-traefik`
- cert-manager: `rex5-cc-mz-prod-cert-manager`
- external-secrets: `rex5-cc-mz-prod-external-secrets`
- Authentik: `rex5-cc-mz-prod-authentik`
- Monitoring: `rex5-cc-mz-prod-monitoring`
- Shared: `rex5-cc-mz-prod-shared`

---

## "How to add a new app" (standard recipe)

1. **Create namespace manifest** (if new):
   - `platform/namespaces/<app>.yaml`
   - Include Pod Security Admission labels (restricted)
   - Reference NetworkPolicy from `platform/policies/`

2. **Add app folder:**
   - `apps/<app>/namespace.yaml` (if not using central namespaces)
   - `apps/<app>/values.yaml` (Helm values, pinned versions)
   - `apps/<app>/externalsecret.yaml` (references to AKV secrets)
   - `apps/<app>/httproute.yaml` (Gateway API routing)

3. **Update Gateway allowedRoutes** (if needed):
   - Add namespace to Gateway listener selector in `platform/traefik/gateway.yaml`

4. **Validate:**
   - `helm template ...`
   - `kubeconform ...`

5. **Commit + PR with checklist.**
   - ArgoCD ApplicationSet will auto-discover the new app folder

---

## Placeholders you must replace (do not commit real secrets)

Use placeholders like:
- `<AKS_NAME>`, `<AKS_RG>`, `<SUBSCRIPTION_ID>`
- `<AZURE_TENANT_ID>`
- `<DNS_ZONE_RESOURCE_GROUP>`
- `<DNS_ZONE_NAME>`
- `<KEYVAULT_NAME>`
- `<DOMAIN>` / `<WILDCARD_DOMAIN>`

**Never commit:**
- client secrets
- private keys
- kubeconfigs
- vault tokens

---

## ADRs (architecture decisions)

If you change any of these, add an ADR in `docs/adr/`:

- ingress model (IngressRoute vs Ingress)
- cert issuance strategy
- secrets strategy / identity model
- namespace/policy model
- ArgoCD revision pinning strategy

Template file: `docs/adr/0000-template.md`

---

## Definition of Done (DoD)

A change is done only when:

- [ ] It's merged to Git
- [ ] ArgoCD is Healthy/Synced (or an incident log explains why not)
- [ ] `logs/commands/...` updated (including failures + DO NOT RETRY if relevant)
- [ ] `logs/prompts/...` updated if AI was used
- [ ] `logs/problems/...` created if debugging was non-trivial or impactful
- [ ] Rollback plan exists in the PR/commit log

---

## Future Improvements (Roadmap)

> These are identified best practices to implement **after** the basic stack is operational.

### Phase 2: ArgoCD Hardening
- [x] **Sync waves and hooks** — Implemented with waves -1 to 5 for dependency ordering
- [x] **Pruning policy** — Automated pruning enabled (`automated.prune: true`)
- [x] **Self-heal policy** — Automated self-heal enabled (`automated.selfHeal: true`)
- [x] **ApplicationSets** — Implemented for workload apps (auto-discovery from `apps/`)
- [ ] **ArgoCD RBAC** — Define user/group permissions for ArgoCD UI/CLI
- [ ] **Notifications** — Slack/PagerDuty alerts on sync failures
- [ ] **Sync windows** — Define production change windows (e.g., no syncs during business hours)
- [ ] **Custom health checks** — ArgoCD resource health for CRDs (HTTPRoute, Certificate, ExternalSecret)

### Phase 3: Observability
- [ ] **Metrics** — Prometheus + Grafana (or Azure Monitor for managed experience)
- [ ] **Logging** — Centralized logging (Loki, Azure Log Analytics)
- [ ] **Tracing** — Distributed tracing (Jaeger, Azure App Insights)
- [ ] **Alerting** — Platform health alerts (cert expiry, pod restarts, sync failures)
- [ ] **SLOs/SLIs** — Define service level objectives for critical services
- [ ] **Dashboards** — ArgoCD dashboard, cluster health, app-specific dashboards

### Phase 4: Security Hardening
- [ ] **Image scanning** — Trivy, Qualys, or Azure Defender for container images
- [ ] **Image signing** — Cosign/Sigstore verification
- [ ] **Allowed registries** — Policy to restrict image sources
- [ ] **Policy enforcement** — Kyverno or OPA/Gatekeeper for:
  - Enforcing Pod Security Standards programmatically
  - Blocking `:latest` tags
  - Requiring resource limits
  - Requiring labels/annotations
- [ ] **Kubernetes RBAC** — Document who can do what in which namespace
- [ ] **Audit logging** — Enable and retain AKS diagnostic/audit logs
- [ ] **Secrets rotation** — Strategy for rotating secrets in Key Vault

### Phase 5: Resource Management
- [ ] **ResourceQuotas** — Per-namespace CPU/memory/object limits
- [ ] **LimitRanges** — Default requests/limits for pods
- [ ] **PodDisruptionBudgets** — HA guarantees during node maintenance
- [ ] **HorizontalPodAutoscaler** — Autoscaling policies for apps

### Phase 6: CI/CD Pipeline
- [ ] **Automated validation** — `kubeconform` + policy checks in CI
- [ ] **PR blocking** — Fail PRs on validation errors
- [ ] **Diff preview** — Show what will change in cluster (ArgoCD diff or similar)
- [ ] **Pre-commit hooks** — Local validation before commit
- [ ] **Progressive delivery** — Argo Rollouts for canary/blue-green deployments

### Phase 7: Disaster Recovery & Upgrades
- [ ] **Backup strategy** — PV backups (Velero), ArgoCD credentials
- [ ] **RTO/RPO targets** — Document recovery objectives
- [ ] **Cluster recreation runbook** — Steps to rebuild from Git
- [ ] **AKS upgrade runbook** — Kubernetes version upgrades
- [ ] **Node pool upgrade runbook** — Rolling node updates
- [ ] **Platform component upgrades** — Traefik, cert-manager, ESO version bumps
- [ ] **CRD upgrade strategy** — Handle breaking CRD changes

### Phase 8: Multi-tenancy & Networking
- [ ] **App-to-app policies** — Define which apps can communicate
- [ ] **Egress policies** — Explicit allow-lists for external services
- [ ] **Service mesh evaluation** — Consider Linkerd/Istio if mTLS or advanced routing needed

### Housekeeping
- [ ] **ADR template** — Create `docs/adr/0000-template.md`
- [ ] **`.gitignore`** — Exclude rendered manifests, kubeconfig, `.terraform/`, etc.
- [ ] **Pre-commit config** — `.pre-commit-config.yaml` for local validation
