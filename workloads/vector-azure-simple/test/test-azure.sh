#!/bin/bash
# Test Vector posting to Azure Log Analytics
# ===========================================
# This script runs Vector locally with demo_logs source
# and posts to Azure Log Analytics via DCR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"

# Get credentials from Terraform
echo "Getting credentials from Terraform..."
cd "$TERRAFORM_DIR"

TENANT_ID=$(terraform output -raw tenant_id)
CLIENT_ID=$(terraform output -raw client_id)
CLIENT_SECRET=$(terraform output -raw client_secret)

if [ -z "$CLIENT_SECRET" ]; then
    echo "ERROR: Could not get client_secret from Terraform"
    echo "Make sure you've run 'terraform apply' first"
    exit 1
fi

# Get OAuth2 bearer token
echo "Fetching OAuth2 bearer token..."
TOKEN_RESPONSE=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "scope=https://monitor.azure.com/.default" \
    -d "grant_type=client_credentials")

AZURE_BEARER_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$AZURE_BEARER_TOKEN" ] || [ "$AZURE_BEARER_TOKEN" == "null" ]; then
    echo "ERROR: Could not get access token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "Token acquired successfully (expires in $(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')s)"
echo ""
echo "Starting Vector with Azure Log Analytics sink..."
echo "Press Ctrl+C to stop"
echo ""

cd "$SCRIPT_DIR"

# Run Vector in Docker with bearer token
docker run --rm -it \
    -v "${SCRIPT_DIR}/vector-azure-test.yaml:/etc/vector/vector.yaml:ro" \
    -e AZURE_BEARER_TOKEN="$AZURE_BEARER_TOKEN" \
    -p 8686:8686 \
    timberio/vector:0.52.0-alpine \
    --config /etc/vector/vector.yaml
