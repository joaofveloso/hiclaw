#!/bin/bash
# setup-higress-gateway.sh - Create Gateway API resources for Higress
# This ensures Higress Gateway listens on port 8080 on container startup
# Called by start-higress-gateway.sh before Higress starts

set -e

# Ensure defaultConfig directory exists
mkdir -p /opt/data/defaultConfig/namespaces
mkdir -p /opt/data/defaultConfig/gatewayclasses
mkdir -p /opt/data/defaultConfig/gateways

# Create Namespace resource
cat > /opt/data/defaultConfig/namespaces/higress-system.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: higress-system
  labels:
    name: higress-system
EOF

# Create GatewayClass resource
cat > /opt/data/defaultConfig/gatewayclasses/higress-gateway.yaml << EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: higress-gateway
spec:
  controllerName: higress.io/gateway-controller
EOF

# Create Gateway resource
cat > /opt/data/defaultConfig/gateways/higress-gateway.yaml << EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: higress-gateway
  namespace: higress-system
  labels:
    higress: higress-system-higress-gateway
spec:
  gatewayClassName: higress-gateway
  listeners:
  - name: http
    protocol: HTTP
    port: 8080
    hostname: "*"
  - name: https
    protocol: HTTPS
    port: 8443
    hostname: "*"
EOF

echo "Gateway resources created in /opt/data/defaultConfig/"
