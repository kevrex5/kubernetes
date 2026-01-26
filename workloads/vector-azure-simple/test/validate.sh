#!/bin/bash
# Vector Configuration Validation Script
# =======================================
# Validates both the local test config and the rendered Helm template

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"
VECTOR_IMAGE="timberio/vector:0.52.0-alpine"

echo "=============================================="
echo "Vector Azure Simple - Configuration Validator"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    echo "Install Docker or use 'vector validate' directly if Vector is installed locally"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${YELLOW}Warning: Helm is not installed. Skipping Helm template validation.${NC}"
    HELM_AVAILABLE=false
else
    HELM_AVAILABLE=true
fi

echo "Step 1: Validating local test config..."
echo "----------------------------------------"
if docker run --rm \
    -v "$SCRIPT_DIR:/etc/vector:ro" \
    -v /tmp:/tmp \
    "$VECTOR_IMAGE" \
    validate --no-environment /etc/vector/vector-local.yaml 2>&1; then
    echo -e "${GREEN}✓ Local test config is valid${NC}"
else
    echo -e "${RED}✗ Local test config validation failed${NC}"
    exit 1
fi
echo ""

if [ "$HELM_AVAILABLE" = true ]; then
    echo "Step 2: Rendering Helm template..."
    echo "-----------------------------------"
    
    # Render the helm template and extract vector.yaml
    cd "$CHART_DIR"
    RENDERED_CONFIG="$SCRIPT_DIR/rendered-vector.yaml"
    
    # Extract just the vector.yaml content from the ConfigMap (stop at next YAML doc)
    helm template test . 2>/dev/null | \
        awk '/vector.yaml: \|/,/^---/' | \
        head -n -1 | \
        tail -n +2 | \
        sed 's/^    //' > "$RENDERED_CONFIG"
    
    if [ ! -s "$RENDERED_CONFIG" ]; then
        echo -e "${RED}✗ Failed to extract vector.yaml from Helm template${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Helm template rendered to test/rendered-vector.yaml${NC}"
    echo ""
    
    echo "Step 3: Validating rendered Helm config..."
    echo "-------------------------------------------"
    # Note: Using --no-environment skips checks for files/env vars that won't exist locally
    VALIDATE_OUTPUT=$(docker run --rm \
        -v "$SCRIPT_DIR:/etc/vector:ro" \
        -e AZURE_DCR_TOKEN=test-token \
        "$VECTOR_IMAGE" \
        validate --no-environment /etc/vector/rendered-vector.yaml 2>&1)
    VALIDATE_EXIT=$?
    
    echo "$VALIDATE_OUTPUT"
    
    # Check if the only errors are expected ones (missing TLS certs, etc.)
    if [ $VALIDATE_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓ Rendered Helm config is valid${NC}"
    elif echo "$VALIDATE_OUTPUT" | grep -q "Could not open certificate file" && \
         ! echo "$VALIDATE_OUTPUT" | grep -qE "syntax error|error\[E"; then
        echo -e "${YELLOW}⚠ Config syntax is valid (TLS cert missing - expected in local test)${NC}"
        VALIDATE_EXIT=0
    else
        echo -e "${RED}✗ Rendered Helm config validation failed${NC}"
        echo ""
        echo "Common issues:"
        echo "  - Missing environment variables (AZURE_DCR_TOKEN)"
        echo "  - Invalid YAML syntax in values.yaml"
        echo "  - Incorrect field names in Vector config"
        exit 1
    fi
else
    echo "Step 2: Skipping Helm template validation (helm not installed)"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}All validations passed!${NC}"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  - Run interactively: docker run -it --rm -v \$(pwd)/test:/etc/vector:ro $VECTOR_IMAGE --config /etc/vector/vector-local.yaml"
echo "  - Send test messages: cat test/test-messages.txt"
