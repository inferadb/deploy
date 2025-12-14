#!/bin/bash
# scripts/dev-down.sh
# Local cluster teardown script for InferaDB development
# Destroys the local Talos cluster created by dev-up.sh

set -euo pipefail

CLUSTER_NAME="inferadb-dev"
KUBECONFIG_PATH="$HOME/.kube/inferadb-dev"

echo "=== Tearing down local Talos cluster ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# Check if cluster exists
if ! talosctl cluster show --provisioner docker 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' not found. Nothing to tear down."
  exit 0
fi

# Destroy the cluster
echo "Destroying Talos cluster..."
talosctl cluster destroy --name "${CLUSTER_NAME}" --provisioner docker

echo ""
echo "Cluster destroyed successfully!"
echo ""

# Optionally remove kubeconfig file
if [ -f "${KUBECONFIG_PATH}" ]; then
  read -p "Remove kubeconfig file at ${KUBECONFIG_PATH}? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "${KUBECONFIG_PATH}"
    echo "Kubeconfig removed."
  else
    echo "Kubeconfig preserved at: ${KUBECONFIG_PATH}"
  fi
fi

echo ""
echo "=== Teardown complete ==="
echo ""
