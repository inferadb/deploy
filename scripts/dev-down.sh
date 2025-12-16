#!/bin/bash
# scripts/dev-down.sh
# Local cluster teardown script for InferaDB development
# Destroys the local Talos cluster created by dev-up.sh

set -euo pipefail

CLUSTER_NAME="inferadb-dev"
KUBE_CONTEXT="admin@${CLUSTER_NAME}"
REGISTRY_NAME="inferadb-registry"

# Tailscale device names created by our ingress
TAILSCALE_DEVICES=("inferadb-api" "inferadb-dashboard")

echo "=== Tearing down local Talos cluster ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# Stop and remove the local registry container (connected to cluster network)
if docker ps -a --filter "name=${REGISTRY_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q "${REGISTRY_NAME}"; then
  echo "Stopping and removing local registry..."
  docker stop "${REGISTRY_NAME}" 2>/dev/null || true
  docker rm "${REGISTRY_NAME}" 2>/dev/null || true
fi

# Clean up Tailscale devices before destroying the cluster
# The Tailscale operator creates devices that persist after cluster deletion
cleanup_tailscale_devices() {
  # Check if we have cached credentials
  TAILSCALE_CREDS_FILE="${HOME}/.config/inferadb/tailscale-credentials"
  if [ -f "${TAILSCALE_CREDS_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${TAILSCALE_CREDS_FILE}"
  fi

  # Need credentials to use API
  if [ -z "${TAILSCALE_CLIENT_ID:-}" ] || [ -z "${TAILSCALE_CLIENT_SECRET:-}" ]; then
    echo "Note: Tailscale credentials not found. Orphaned devices may remain in your Tailscale admin."
    echo "      You can manually remove them at: https://login.tailscale.com/admin/machines"
    return 0
  fi

  echo "Cleaning up Tailscale devices..."

  # Get OAuth token
  TOKEN_RESPONSE=$(curl -s -X POST "https://api.tailscale.com/api/v2/oauth/token" \
    -u "${TAILSCALE_CLIENT_ID}:${TAILSCALE_CLIENT_SECRET}" \
    -d "grant_type=client_credentials" 2>/dev/null || echo "")

  ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)

  if [ -z "${ACCESS_TOKEN}" ]; then
    echo "  Could not obtain Tailscale API token. Skipping device cleanup."
    return 0
  fi

  # Get tailnet name from local CLI or use "-" for default
  TAILNET="-"

  # List devices and find ones matching our names
  DEVICES_RESPONSE=$(curl -s -X GET "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/devices" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null || echo "")

  # Skip if no devices response
  if [ -z "${DEVICES_RESPONSE}" ] || ! echo "${DEVICES_RESPONSE}" | grep -q '"devices"'; then
    echo "  No devices found or API unavailable. Skipping device cleanup."
    return 0
  fi

  for device_name in "${TAILSCALE_DEVICES[@]}"; do
    # Find device ID by name (device names in API include the tailnet suffix)
    DEVICE_ID=$(echo "${DEVICES_RESPONSE}" | grep -o '"id":"[^"]*"[^}]*"name":"[^"]*'"${device_name}"'[^"]*"' | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

    if [ -n "${DEVICE_ID}" ]; then
      echo "  Removing Tailscale device: ${device_name} (${DEVICE_ID})..."
      curl -s -X DELETE "https://api.tailscale.com/api/v2/device/${DEVICE_ID}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null || true
    fi
  done

  # Also clean up the operator device if present
  OPERATOR_ID=$(echo "${DEVICES_RESPONSE}" | grep -o '"id":"[^"]*"[^}]*"name":"[^"]*tailscale-operator[^"]*"' | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  if [ -n "${OPERATOR_ID}" ]; then
    echo "  Removing Tailscale device: tailscale-operator (${OPERATOR_ID})..."
    curl -s -X DELETE "https://api.tailscale.com/api/v2/device/${OPERATOR_ID}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" 2>/dev/null || true
  fi

  echo "  Tailscale cleanup complete."
}

cleanup_tailscale_devices

# Check if Docker containers exist for this cluster
if ! docker ps -a --filter "name=${CLUSTER_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  echo "No running cluster found for '${CLUSTER_NAME}'."

  # Clean up stale talosctl contexts (including numbered variants like inferadb-dev-1)
  for ctx in $(talosctl config contexts 2>/dev/null | awk '{print $2}' | grep "^${CLUSTER_NAME}"); do
    echo "Cleaning up stale talosctl context: ${ctx}..."
    # Switch away from current context if needed, then remove
    talosctl config context "" 2>/dev/null || true
    talosctl config remove "${ctx}" --noconfirm 2>/dev/null || true
  done

  # Clean up stale kubectl context if it exists
  if kubectl config get-contexts -o name 2>/dev/null | grep -q "${KUBE_CONTEXT}"; then
    echo "Cleaning up stale kubectl context..."
    kubectl config delete-context "${KUBE_CONTEXT}" 2>/dev/null || true
    kubectl config delete-cluster "${CLUSTER_NAME}" 2>/dev/null || true
    kubectl config delete-user "${KUBE_CONTEXT}" 2>/dev/null || true
  fi

  echo "Nothing to tear down."
  exit 0
fi

# Destroy the cluster
echo "Destroying Talos cluster..."
talosctl cluster destroy --name "${CLUSTER_NAME}"

# Clean up talosctl contexts (including numbered variants like inferadb-dev-1)
echo "Cleaning up talosctl contexts..."
for ctx in $(talosctl config contexts 2>/dev/null | awk '{print $2}' | grep "^${CLUSTER_NAME}"); do
  talosctl config context "" 2>/dev/null || true
  talosctl config remove "${ctx}" --noconfirm 2>/dev/null || true
done

# Clean up kubectl context
echo "Cleaning up kubectl context..."
kubectl config delete-context "${KUBE_CONTEXT}" 2>/dev/null || true
kubectl config delete-cluster "${CLUSTER_NAME}" 2>/dev/null || true
kubectl config delete-user "${KUBE_CONTEXT}" 2>/dev/null || true

echo ""
echo "Cluster destroyed successfully!"
echo ""
echo "=== Teardown complete ==="
echo ""
