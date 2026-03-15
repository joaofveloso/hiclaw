# Higress Gateway Port 8080 Fix

## Problem

Higress Gateway was not listening on port 8080, causing the Manager agent to fail with:
```
ERROR: Higress Gateway did not become available within 180s
```

## Root Cause

Higress Gateway requires Gateway API resources to create listeners. The `--gatewayHttpPort=8080` flag only specifies which port to use for Gateway resources - it does not create listeners by itself.

The Gateway resources were missing:
- Namespace: `higress-system`
- GatewayClass: `higress-gateway`
- Gateway: `higress-gateway` (with labels matching Higress selector)

## Solution

The fix consists of three components:

### 1. Gateway Resources Setup (`setup-higress-gateway.sh`)

Creates the required Gateway API resources in `/opt/data/defaultConfig/` during container build:

- `namespaces/higress-system.yaml` - Namespace for Higress resources
- `gatewayclasses/higress-gateway.yaml` - GatewayClass resource
- `gateways/higress-gateway.yaml` - Gateway resource with port 8080/8443 listeners

These resources are copied to `/data/` by the Higress API server on container startup.

### 2. Updated Higress Startup (`start-higress-gateway.sh`)

Wrapper script that:
- Runs the Gateway resources setup
- Starts Higress with the correct flags
- Uses the original Higress startup logic

### 3. Readiness Check (`ensure-higress-gateway-ready.sh`)

Post-startup monitoring script that:
- Waits for Higress to start
- Checks if port 8080 is listening
- If not available after 60 seconds, restarts Higress
- Retries up to 3 times with 15-second waits
- Ensures port 8080 is available before Manager agent starts

## How It Works

```
Container Startup
    ↓
Priority 200: higress-apiserver (copies resources to /data/)
    ↓
Priority 250: higress-gateway-setup (creates Gateway resources)
    ↓
Priority 300: higress-controller (starts Higress)
    ↓
Priority 400: higress-pilot (starts Envoy)
    ↓
Priority 500: higress-gateway
    ↓
Priority 600: higress-console
    ↓
Priority 850: ensure-higress-gateway-ready (monitors port 8080)
    ↓
Priority 800: manager-agent (starts when port 8080 is ready)
    ↓
Port 8080 available ✅
```

## Files Modified

1. **supervisord.conf** - Updated to use new startup scripts and add readiness check
2. **scripts/init/setup-higress-gateway.sh** - Creates Gateway resources
3. **scripts/init/start-higress-gateway.sh** - Starts Higress with setup
4. **scripts/init/ensure-higress-gateway-ready.sh** - Ensures port 8080 is available

## Verification

```bash
# Build the container
docker build -t hiclaw-manager:latest -f manager/Dockerfile manager

# Start the container
docker run -d --name hiclaw-manager hiclaw-manager:latest

# Wait for startup (60-90 seconds)
sleep 60

# Check port 8080
docker exec hiclaw-manager ss -tlnp | grep 8080

# Test connectivity
docker exec hiclaw-manager curl -I http://127.0.0.1:8080/
```

Expected output:
```
LISTEN 0  4096    0.0.0.0:8080    0.0.0.0:*    users:(("envoy",pid=...))
HTTP/1.1 200 OK
```

## Troubleshooting

If port 8080 is not available:

1. Check Gateway resources exist:
   ```bash
   docker exec hiclaw-manager ls -la /opt/data/defaultConfig/namespaces/
   docker exec hiclaw-manager ls -la /opt/data/defaultConfig/gateways/
   ```

2. Check Higress logs:
   ```bash
   docker exec hiclaw-manager tail -50 /var/log/hiclaw/higress-controller.log
   ```

3. Check ensure-gateway-ready logs:
   ```bash
   docker exec hiclaw-manager tail -50 /var/log/hiclaw/ensure-gateway-ready.log
   ```

4. Check listener state:
   ```bash
   docker exec hiclaw-manager curl -s "http://127.0.0.1:15000/listeners?format=json" | python3 -m json.tool | grep -A 10 "8080"
   ```

## Technical Details

### Higress Configuration

Higress is configured with these flags:
- `--gatewaySelectorKey=higress`
- `--gatewaySelectorValue=higress-system-higress-gateway`
- `--gatewayHttpPort=8080`
- `--gatewayHttpsPort=8443`

The Gateway resource must have labels matching the selector:
```yaml
metadata:
  labels:
    higress: higress-system-higress-gateway
```

### Listener Initialization

When Higress starts:
1. Pilot discovery service watches for Gateway resources
2. When Gateway with matching labels is found, creates Envoy listener
3. Listener configuration includes WasmPlugins that need to initialize
4. Listener transitions from `warming_state` → `active_state`
5. Port 8080 becomes available

If WasmPlugins fail to initialize, the listener remains in `warming_state` and port 8080 never opens. The readiness check script detects this and restarts Higress to force re-initialization.

### Data Persistence

- `/opt/data/defaultConfig/` - Created at build time, copied to `/data/` at runtime
- `/data/` - Persisted volume, survives container restarts
- Gateway resources in `/data/` are loaded by the API server

## Related Components

- API Server: `/usr/local/bin/start-apiserver.sh` (priority 200)
- Higress Controller: New startup script (priority 300)
- Higress Pilot: `/usr/local/bin/start-pilot.sh` (priority 400)
- Higress Gateway: `/usr/local/bin/start-gateway.sh` (priority 500)
- Manager Agent: `/opt/hiclaw/scripts/init/start-manager-agent.sh` (priority 800)
- Readiness Check: New ensure script (priority 850)
