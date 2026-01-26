# Vector Test Infrastructure - Terraform

Creates Azure Log Analytics infrastructure for testing the Vector CEF pipeline.

## What This Creates

1. **Custom Table** (`VectorCEF_CL`) - CEF schema table in Log Analytics
2. **Data Collection Rule** (kind=Direct) - With automatic log ingestion endpoint

> **Note**: Using `kind=Direct` automatically creates a log ingestion endpoint. No separate Data Collection Endpoint (DCE) resource is needed.

## Prerequisites

- Azure CLI authenticated (`az login`)
- Terraform >= 1.5.0
- Existing Log Analytics Workspace
- Existing Resource Group

## Quick Start

```bash
cd test/terraform

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Initialize and apply
terraform init
terraform plan
terraform apply

# Get the outputs for Vector configuration
terraform output -raw vector_dcr_uri
terraform output -raw curl_test_command
```

## Outputs

| Output | Description |
|--------|-------------|
| `dcr_immutable_id` | DCR immutable ID (dcr-xxxxxxxx) |
| `logs_ingestion_endpoint` | Log ingestion URL (https://xxx.ingest.monitor.azure.com) |
| `stream_name` | Stream name (Custom-VectorCEF) |
| `vector_dcr_uri` | Complete URI for Vector HTTP sink |
| `vector_config_snippet` | Ready-to-use Vector config |
| `curl_test_command` | Curl command to test the endpoint |

## Testing the Endpoint

### 1. Test with curl

```bash
# Get outputs
eval "$(terraform output -raw curl_test_command)"
```

### 2. Test with Vector

```bash
# Export the DCR URI
export VECTOR_DCR_URI=$(terraform output -raw vector_dcr_uri)

# Get Azure token
export AZURE_DCR_TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)

# Run Vector with test config (update the URI in your config first)
cd ../..
./test/validate.sh
```

### 3. Verify in Log Analytics

```kusto
// Wait 2-5 minutes, then query:
VectorCEF_CL
| take 10
```

## Authentication Options

### Option 1: Short-lived Token (Testing Only)

```bash
TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)
```

⚠️ Tokens expire in ~1 hour.

### Option 2: Service Principal (Production)

```bash
# Create SP with monitoring permissions
az ad sp create-for-rbac --name "sp-vector-test" --role "Monitoring Metrics Publisher" \
  --scopes "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Insights/dataCollectionRules/<dcr-name>"

# Get token
TOKEN=$(az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv)
```

### Option 3: Managed Identity (Kubernetes)

For production in AKS, use Azure Workload Identity with the Vector service account.

## Clean Up

```bash
terraform destroy
```

## Troubleshooting

### "Table already exists"

The table may have been created previously. Import it:

```bash
terraform import 'azapi_resource.custom_table' '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<law>/tables/VectorCEF_CL'
```

### "401 Unauthorized"

Token expired or missing permissions. Get a new token:

```bash
az account get-access-token --resource https://monitor.azure.com --query accessToken -o tsv
```

### "Stream not found"

Ensure the stream name matches exactly: `Custom-VectorCEF` (case-sensitive).

### Data not appearing in Log Analytics

- Wait 2-5 minutes for ingestion
- Check the `TimeGenerated` field is a valid ISO 8601 timestamp
- Verify the JSON payload matches the schema
