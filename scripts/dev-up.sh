#!/bin/bash
# scripts/dev-up.sh
# Local Talos cluster creation script for InferaDB development
# Creates a Talos cluster using Docker provisioner with default flannel CNI

set -euo pipefail

CLUSTER_NAME="inferadb-dev"
KUBE_CONTEXT="admin@${CLUSTER_NAME}"

echo "=== Creating local Talos cluster for InferaDB development ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# Check if cluster already exists
if talosctl cluster show --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  echo "To recreate it, first run: ./scripts/dev-down.sh"
  exit 1
fi

# Create cluster using talosctl (Docker provisioner)
# Uses default flannel CNI for simplicity in local dev
# Production uses Cilium via Flux
echo "Creating Talos cluster with Docker provisioner..."

talosctl cluster create \
  --name "${CLUSTER_NAME}" \
  --workers 1 \
  --controlplanes 1 \
  --provisioner docker \
  --kubernetes-version 1.30.0 \
  --wait-timeout 10m

echo ""
echo "Cluster created successfully!"
echo ""

# Set kubectl context
echo "Setting kubectl context to ${KUBE_CONTEXT}..."
kubectl config use-context "${KUBE_CONTEXT}"

# Verify cluster is ready
echo "Verifying cluster is ready..."
kubectl get nodes

echo ""

# Bootstrap Flux (simplified for dev - no GitHub, use local path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUX_DIR="${SCRIPT_DIR}/../flux/clusters/dev-local/flux-system"

echo "Bootstrapping Flux..."
if [ -f "${FLUX_DIR}/gotk-components.yaml" ]; then
  kubectl apply -f "${FLUX_DIR}/gotk-components.yaml"
  kubectl apply -f "${FLUX_DIR}/gotk-sync.yaml"
  echo "Flux bootstrapped successfully!"
else
  echo "Note: Flux manifests not found at ${FLUX_DIR}/"
  echo "Skipping Flux bootstrap. Generate with: flux install --export > gotk-components.yaml"
fi

echo ""
echo "=== Development environment ready! ==="
echo ""
echo "Cluster context: ${KUBE_CONTEXT}"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -A                    # List all pods"
echo "  kubectl get nodes                      # List nodes"
echo "  talosctl dashboard --nodes 10.5.0.2    # Talos dashboard"
echo ""
echo "To destroy this cluster, run:"
echo "  ./scripts/dev-down.sh"
echo ""
