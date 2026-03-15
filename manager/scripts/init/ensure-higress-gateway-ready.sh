#!/bin/bash
# ensure-higress-gateway-ready.sh - Ensure Higress Gateway port 8080 is available
# This script runs after Higress starts and ensures port 8080 becomes available
# It handles the timing issue where the listener gets stuck in warming_state

set -e

SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
source "$SCRIPT_DIR/base.sh"

LOG_FILE="/var/log/hiclaw/ensure-gateway-ready.log"
MAX_RETRIES=3
RETRY_DELAY=15
LISTENER_TIMEOUT=60

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_port_8080() {
    ss -tlnp | grep -q ":8080 "
}

wait_for_higress() {
    for i in $(seq 1 60); do
        if pgrep -f "higress serve" > /dev/null; then
            log "Higress process detected"
            return 0
        fi
        sleep 1
    done
    log "ERROR: Higress process not detected after 60 seconds"
    return 1
}

wait_for_envoy() {
    for i in $(seq 1 90); do
        if curl -s http://127.0.0.1:15000/stats > /dev/null 2>&1; then
            log "Envoy admin endpoint available"
            return 0
        fi
        sleep 1
    done
    log "WARNING: Envoy admin endpoint not available after 90 seconds"
    return 0
}

restart_higress() {
    log "Restarting Higress..."
    pkill -9 -f "higress serve"
    sleep 5
    log "Waiting for Higress restart..."

    # Wait for Higress to restart
    for i in $(seq 1 30); do
        if pgrep -f "higress serve" > /dev/null; then
            log "Higress restarted"
            break
        fi
        sleep 1
    done
    sleep 5
}

main() {
    log "=== Higress Gateway readiness check started ==="

    # Wait for Higress to start
    wait_for_higress || return 1

    # Wait for Envoy to be available
    wait_for_envoy

    # Wait for listener to be created and become active
    log "Waiting for port 8080 to become available (timeout: $LISTENER_TIMEOUT seconds)..."

    for i in $(seq 1 $LISTENER_TIMEOUT); do
        if check_port_8080; then
            log "✅ Port 8080 is listening!"
            log "=== Higress Gateway readiness check completed successfully ==="
            return 0
        fi

        # Log progress every 20 seconds
        if [ $((i % 20)) -eq 0 ] && [ $i -gt 0 ]; then
            log "Checkpoint: $i seconds elapsed, port 8080 not yet listening"

            # Check if listener exists
            LISTENER_INFO=$(curl -s "http://127.0.0.1:15000/listeners" 2>/dev/null | grep 8080 || echo "")
            if [ -n "$LISTENER_INFO" ]; then
                log "Listener exists: $LISTENER_INFO"
            fi
        fi

        sleep 1
    done

    # Port 8080 not available after timeout
    log "⚠️  Port 8080 not available after $LISTENER_TIMEOUT seconds"

    # Try restarting Higress
    for retry in $(seq 1 $MAX_RETRIES); do
        log "Retry $retry/$MAX_RETRIES: Restarting Higress..."
        restart_higress

        # Wait for port 8080 after restart
        for i in $(seq 1 $RETRY_DELAY); do
            if check_port_8080; then
                log "✅ Port 8080 is listening after restart!"
                log "=== Higress Gateway readiness check completed successfully ==="
                return 0
            fi
            sleep 1
        done
    done

    log "❌ Failed to get port 8080 listening after $MAX_RETRIES retries"
    log "=== Higress Gateway readiness check failed ==="
    return 1
}

main "$@"
