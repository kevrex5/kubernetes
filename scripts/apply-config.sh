#!/bin/bash
# =============================================================================
# apply-config.sh - Apply environment configuration to manifests
# =============================================================================
# This script reads values from environments/<env>/config.yaml and applies them
# to all platform and application manifests using envsubst.
#
# Usage:
#   ./scripts/apply-config.sh [environment]
#   ./scripts/apply-config.sh prod  (default)
#
# The script:
# 1. Reads the config.yaml ConfigMap and extracts data values
# 2. Exports them as environment variables
# 3. Runs envsubst on template files to generate final manifests
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV="${1:-prod}"
CONFIG_FILE="$REPO_ROOT/environments/$ENV/config.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

log_info "Applying configuration from: $CONFIG_FILE"

# Extract values from ConfigMap and export as environment variables
# Uses yq to parse YAML - install with: brew install yq or apt install yq
if ! command -v yq &> /dev/null; then
    log_error "yq is required but not installed. Install with: brew install yq"
    exit 1
fi

# Export all data values from the ConfigMap
while IFS='=' read -r key value; do
    if [[ -n "$key" && -n "$value" ]]; then
        export "$key"="$value"
        log_info "  $key=$value"
    fi
done < <(yq eval '.data | to_entries | .[] | .key + "=" + .value' "$CONFIG_FILE")

# Function to process a template file
process_template() {
    local template="$1"
    local output="${template%.tmpl}"
    
    if [[ "$template" == *.tmpl ]]; then
        log_info "Processing: $template -> $output"
        envsubst < "$template" > "$output"
    fi
}

# Find and process all .tmpl files
log_info "Processing template files..."
find "$REPO_ROOT" -name "*.yaml.tmpl" -o -name "*.yml.tmpl" | while read -r template; do
    process_template "$template"
done

log_info "Configuration applied successfully!"
log_info ""
log_info "Next steps:"
log_info "  1. Review generated files"
log_info "  2. Commit changes: git add -A && git commit -m 'config: apply $ENV configuration'"
log_info "  3. Push and let ArgoCD sync"
