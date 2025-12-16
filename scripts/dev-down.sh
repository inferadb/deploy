#!/bin/bash
# scripts/dev-down.sh
# Local cluster teardown script for InferaDB development
# Destroys the local Talos cluster created by dev-up.sh

set -euo pipefail

CLUSTER_NAME="inferadb-dev"
KUBE_CONTEXT="admin@${CLUSTER_NAME}"
REGISTRY_NAME="inferadb-registry"

echo "=== Tearing down local Talos cluster ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# Stop and remove the local registry container (connected to cluster network)
if docker ps -a --filter "name=${REGISTRY_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q "${REGISTRY_NAME}"; then
  echo "Stopping and removing local registry..."
  docker stop "${REGISTRY_NAME}" 2>/dev/null || true
  docker rm "${REGISTRY_NAME}" 2>/dev/null || true
fi

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
