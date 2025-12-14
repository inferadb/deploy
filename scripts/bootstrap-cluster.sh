#!/bin/bash
# scripts/bootstrap-cluster.sh
# Full cluster bootstrap script for InferaDB
# Provisions infrastructure with Terraform, configures Talos, installs Cilium, and bootstraps Flux

set -euo pipefail

# Parse arguments with defaults
ENVIRONMENT="${1:-staging}"
REGION="${2:-nyc1}"
PROVIDER="${3:-aws}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Bootstrapping InferaDB Cluster ==="
echo "Environment: ${ENVIRONMENT}"
echo "Region:      ${REGION}"
echo "Provider:    ${PROVIDER}"
echo ""

# Validate environment
if [[ ! "${ENVIRONMENT}" =~ ^(staging|production)$ ]]; then
  echo "Error: Environment must be 'staging' or 'production'"
  exit 1
fi

# Phase 1: Terraform provisioning
echo "=== Phase 1: Terraform Infrastructure Provisioning ==="
cd "${REPO_ROOT}/terraform/environments/${ENVIRONMENT}"

echo "Initializing Terraform..."
terraform init

echo "Applying Terraform configuration..."
terraform apply -var="region=${REGION}" -var="provider=${PROVIDER}" -auto-approve

echo ""
echo "Extracting Terraform outputs..."
CONTROL_PLANE_ENDPOINT=$(terraform output -raw control_plane_endpoint)
NODE_IPS_JSON=$(terraform output -json node_ips)

# Convert JSON array to bash array
readarray -t NODE_IPS < <(echo "${NODE_IPS_JSON}" | jq -r '.[]')

echo "Control Plane Endpoint: ${CONTROL_PLANE_ENDPOINT}"
echo "Node IPs: ${NODE_IPS[*]}"
echo ""

# Phase 2: Talos configuration using talhelper
echo "=== Phase 2: Talos Configuration ==="
cd "${REPO_ROOT}/talos"

export TALOS_ENDPOINT="${CONTROL_PLANE_ENDPOINT}"
echo "Talos endpoint: ${TALOS_ENDPOINT}"

echo "Generating Talos configuration with talhelper..."
talhelper genconfig --config-file talconfig.yaml --env-file ".env.${ENVIRONMENT}"

echo "Applying Talos configuration to nodes..."
for i in "${!NODE_IPS[@]}"; do
  NODE_IP="${NODE_IPS[$i]}"
  CONFIG_FILE="./clusterconfig/inferadb-${ENVIRONMENT}-${REGION}-controlplane-$((i+1)).yaml"

  echo "  Applying config to node ${NODE_IP} ($(basename "${CONFIG_FILE}"))..."
  talosctl apply-config --nodes "${NODE_IP}" --file "${CONFIG_FILE}"
done

echo ""
echo "Bootstrapping Talos cluster..."
talosctl bootstrap --nodes "${NODE_IPS[0]}"

echo "Waiting for Kubernetes API server to be ready..."
sleep 30

echo ""

# Phase 3: CNI installation
echo "=== Phase 3: Cilium CNI Installation ==="
export KUBECONFIG="./clusterconfig/kubeconfig"

echo "Installing Cilium..."
cilium install --helm-set ipam.mode=kubernetes

echo "Waiting for Cilium to be ready..."
cilium status --wait

echo "Cilium installation complete!"
echo ""

# Phase 4: Secret bootstrapping
echo "=== Phase 4: Secret Bootstrapping ==="
cd "${REPO_ROOT}"

echo "Running bootstrap-secrets.sh..."
"${SCRIPT_DIR}/bootstrap-secrets.sh" "${ENVIRONMENT}" "${REGION}"

echo ""

# Phase 5: Flux bootstrap
echo "=== Phase 5: Flux GitOps Bootstrap ==="

echo "Bootstrapping Flux from GitHub repository..."
flux bootstrap github \
  --owner=inferadb \
  --repository=inferadb-deploy \
  --branch=main \
  --path="./flux/clusters/${ENVIRONMENT}-${REGION}" \
  --personal

echo ""
echo "=== Cluster Bootstrap Complete ==="
echo ""
echo "Cluster: ${ENVIRONMENT}-${REGION}"
echo "Provider: ${PROVIDER}"
echo "Kubeconfig: ${REPO_ROOT}/talos/clusterconfig/kubeconfig"
echo ""
echo "To use this cluster, run:"
echo "  export KUBECONFIG=${REPO_ROOT}/talos/clusterconfig/kubeconfig"
echo ""
echo "To check Flux status:"
echo "  flux get all -A"
echo ""
echo "To check pod status:"
echo "  kubectl get pods -A"
echo ""
