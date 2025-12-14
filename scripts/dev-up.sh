#!/bin/bash
# scripts/dev-up.sh
# Local Talos cluster creation script for InferaDB development
# Creates a single-node Talos cluster using Docker provisioner with Cilium CNI

set -euo pipefail

CLUSTER_NAME="inferadb-dev"
KUBECONFIG_PATH="$HOME/.kube/inferadb-dev"

echo "=== Creating local Talos cluster for InferaDB development ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo ""

# Create cluster using talosctl (Docker provisioner)
echo "Creating Talos cluster with Docker provisioner..."

# Create temporary patch file
PATCH_FILE=$(mktemp)
cat > "${PATCH_FILE}" <<'EOF'
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: "true"
  network:
    interfaces:
      - interface: eth0
        dhcp: true
cluster:
  network:
    cni:
      name: none
EOF

talosctl cluster create \
  --name "${CLUSTER_NAME}" \
  --workers 1 \
  --controlplanes 1 \
  --provisioner docker \
  --kubernetes-version 1.30.0 \
  --config-patch-control-plane "@${PATCH_FILE}"

rm -f "${PATCH_FILE}"

echo ""
echo "Cluster created successfully!"
echo ""

# Get kubeconfig
echo "Fetching kubeconfig..."
talosctl kubeconfig --nodes 127.0.0.1 -f "${KUBECONFIG_PATH}"
export KUBECONFIG="${KUBECONFIG_PATH}"

echo "Kubeconfig saved to: ${KUBECONFIG_PATH}"
echo ""

# Install Cilium (required before any workloads)
echo "Installing Cilium CNI..."
cilium install --helm-set ipam.mode=kubernetes

echo ""
echo "Waiting for Cilium to be ready..."
cilium status --wait

echo ""
echo "Cilium installation complete!"
echo ""

# Bootstrap Flux (simplified for dev - no GitHub, use local path)
echo "Bootstrapping Flux..."
if [ -f "flux/clusters/dev-local/flux-system/gotk-components.yaml" ]; then
  kubectl apply -f flux/clusters/dev-local/flux-system/gotk-components.yaml
  kubectl apply -f flux/clusters/dev-local/flux-system/gotk-sync.yaml
  echo "Flux bootstrapped successfully!"
else
  echo "Warning: Flux manifests not found at flux/clusters/dev-local/flux-system/"
  echo "Skipping Flux bootstrap. You can apply them later manually."
fi

echo ""
echo "=== Development environment ready! ==="
echo ""
echo "To use this cluster, run:"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
echo ""
echo "Useful commands:"
echo "  Dashboard:  kubectl port-forward -n inferadb svc/inferadb-dashboard 3000:3000"
echo "  Engine API: kubectl port-forward -n inferadb svc/inferadb-engine 8080:8080"
echo "  Control API: kubectl port-forward -n inferadb svc/inferadb-control 8081:8081"
echo ""
echo "To destroy this cluster, run:"
echo "  ./scripts/dev-down.sh"
echo ""
