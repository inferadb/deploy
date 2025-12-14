#!/bin/bash
# scripts/dev-down.sh
# Local cluster teardown script for InferaDB development
# Destroys the local Talos cluster created by dev-up.sh

set -euo pipefail

CLUSTER_NAME="inferadb-dev"

echo "=== Tearing down local Talos cluster ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# Check if cluster exists
if ! talosctl cluster show --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER_NAME}' not found. Nothing to tear down."
  exit 0
fi

# Destroy the cluster
echo "Destroying Talos cluster..."
talosctl cluster destroy --name "${CLUSTER_NAME}"

echo ""
echo "Cluster destroyed successfully!"
echo ""
echo "=== Teardown complete ==="
echo ""
