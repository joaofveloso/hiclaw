#!/bin/bash
# start-higress-gateway.sh - Start Higress Gateway with setup
# This script:
# 1. Creates Gateway resources if they don't exist
# 2. Starts Higress
# 3. Ensures port 8080 becomes available

set -e

SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/base.sh"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Setup Gateway resources
log "Setting up Higress Gateway resources..."
/opt/hiclaw/scripts/init/setup-higress-gateway.sh

# Wait for API server to be ready
log "Waiting for API server..."
waitForApiServer

# Start Higress
log "Starting Higress Gateway..."
exec /usr/local/bin/higress \
    serve \
    --kubeconfig=/app/kubeconfig \
    --gatewaySelectorKey=higress \
    --gatewaySelectorValue=higress-system-higress-gateway \
    --gatewayHttpPort=${GATEWAY_HTTP_PORT:-8080} \
    --gatewayHttpsPort=${GATEWAY_HTTPS_PORT:-8443} \
    --ingressClass=
