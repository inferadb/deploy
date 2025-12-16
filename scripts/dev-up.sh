#!/bin/bash
# scripts/dev-up.sh
# Local Talos cluster creation script for InferaDB development
# Creates a Talos cluster using Docker provisioner with default flannel CNI
# and deploys the full InferaDB stack (FDB, engine, control, dashboard)

set -euo pipefail

CLUSTER_NAME="inferadb-dev"
KUBE_CONTEXT="admin@${CLUSTER_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/.."

# Parse arguments
BUILD_IMAGES=true
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-build)
      BUILD_IMAGES=false
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Creates a local Talos Kubernetes cluster and deploys the full InferaDB stack."
      echo ""
      echo "Options:"
      echo "  --skip-build   Skip building container images (use existing images)"
      echo "  --help         Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0               # Build images and deploy full stack"
      echo "  $0 --skip-build  # Deploy using existing images"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "=== Creating local Talos cluster for InferaDB development ==="
echo "Cluster name: ${CLUSTER_NAME}"
echo "Build images: ${BUILD_IMAGES}"
echo ""

# Check if cluster already exists (by checking for Docker containers)
if docker ps -a --filter "name=${CLUSTER_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  echo "To recreate it, first run: ./scripts/dev-down.sh"
  exit 1
fi

# Clean up any stale talosctl contexts to prevent "-1" suffix on new cluster
for ctx in $(talosctl config contexts 2>/dev/null | awk '{print $2}' | grep "^${CLUSTER_NAME}"); do
  echo "Cleaning up stale talosctl context: ${ctx}..."
  talosctl config context "" 2>/dev/null || true
  talosctl config remove "${ctx}" --noconfirm 2>/dev/null || true
done

# Clean up stale kubectl contexts
if kubectl config get-contexts -o name 2>/dev/null | grep -q "^admin@${CLUSTER_NAME}"; then
  echo "Cleaning up stale kubectl context..."
  kubectl config delete-context "${KUBE_CONTEXT}" 2>/dev/null || true
  kubectl config delete-cluster "${CLUSTER_NAME}" 2>/dev/null || true
  kubectl config delete-user "${KUBE_CONTEXT}" 2>/dev/null || true
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
  --kubernetes-version 1.32.0 \
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
FLUX_DIR="${DEPLOY_DIR}/flux/clusters/dev-local/flux-system"

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

# Deploy InferaDB applications
echo "=== Deploying InferaDB applications ==="
echo ""

# Get the repo root (parent of deploy/)
REPO_ROOT="${DEPLOY_DIR}/.."

# Set up local registry for image loading into Talos cluster
# The registry runs on the same Docker network as the Talos containers
REGISTRY_NAME="inferadb-registry"
REGISTRY_PORT=5050

# Start or reuse local registry
if docker ps --filter "name=${REGISTRY_NAME}" --format '{{.Names}}' | grep -q "${REGISTRY_NAME}"; then
  echo "Using existing local registry..."
else
  echo "Starting local registry for image loading..."
  # Get the Docker network used by Talos cluster
  TALOS_NETWORK=$(docker network ls --filter "name=${CLUSTER_NAME}" --format '{{.Name}}' | head -1)
  if [ -z "${TALOS_NETWORK}" ]; then
    TALOS_NETWORK="${CLUSTER_NAME}"
  fi

  docker run -d \
    --name "${REGISTRY_NAME}" \
    --network "${TALOS_NETWORK}" \
    -p ${REGISTRY_PORT}:5000 \
    --restart always \
    registry:2

  # Wait for registry to be ready
  echo "Waiting for registry to be ready..."
  sleep 3
fi

# Get registry IP on the Talos network for in-cluster access
REGISTRY_IP=$(docker inspect "${REGISTRY_NAME}" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
echo "Registry available at ${REGISTRY_IP}:5000 (in-cluster) and localhost:${REGISTRY_PORT} (host)"

# Configure Talos nodes to allow insecure registry (HTTP instead of HTTPS)
echo "Configuring Talos nodes for insecure registry access..."
TALOS_CONTROLPLANE_IP=$(docker inspect "${CLUSTER_NAME}-controlplane-1" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
TALOS_WORKER_IP=$(docker inspect "${CLUSTER_NAME}-worker-1" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)

cat > /tmp/talos-registry-patch.yaml <<EOF
machine:
  registries:
    mirrors:
      ${REGISTRY_IP}:5000:
        endpoints:
          - http://${REGISTRY_IP}:5000
    config:
      ${REGISTRY_IP}:5000:
        tls:
          insecureSkipVerify: true
EOF

# Apply registry config to both Talos nodes
for NODE_IP in "${TALOS_CONTROLPLANE_IP}" "${TALOS_WORKER_IP}"; do
  if [ -n "${NODE_IP}" ]; then
    echo "  Patching Talos node ${NODE_IP}..."
    talosctl patch machineconfig --nodes "${NODE_IP}" --patch @/tmp/talos-registry-patch.yaml 2>/dev/null || true
  fi
done
rm -f /tmp/talos-registry-patch.yaml
echo ""

# Build and push container images unless skipped
if [ "${BUILD_IMAGES}" = true ]; then
  echo "Building and pushing container images..."
  echo ""

  # Build engine image
  echo "Building inferadb-engine image..."
  if [ -f "${REPO_ROOT}/engine/Dockerfile" ]; then
    docker build -t inferadb-engine:latest "${REPO_ROOT}/engine"
    docker tag inferadb-engine:latest "localhost:${REGISTRY_PORT}/inferadb-engine:latest"
    docker push "localhost:${REGISTRY_PORT}/inferadb-engine:latest"
    echo "Engine image built and pushed!"
  else
    echo "Warning: engine/Dockerfile not found, skipping..."
  fi

  # Build control image
  echo "Building inferadb-control image..."
  if [ -f "${REPO_ROOT}/control/Dockerfile" ]; then
    docker build -t inferadb-control:latest "${REPO_ROOT}/control"
    docker tag inferadb-control:latest "localhost:${REGISTRY_PORT}/inferadb-control:latest"
    docker push "localhost:${REGISTRY_PORT}/inferadb-control:latest"
    echo "Control image built and pushed!"
  else
    echo "Warning: control/Dockerfile not found, skipping..."
  fi

  # Build dashboard image
  echo "Building inferadb-dashboard image..."
  if [ -f "${REPO_ROOT}/dashboard/Dockerfile" ]; then
    docker build -t inferadb-dashboard:latest "${REPO_ROOT}/dashboard"
    docker tag inferadb-dashboard:latest "localhost:${REGISTRY_PORT}/inferadb-dashboard:latest"
    docker push "localhost:${REGISTRY_PORT}/inferadb-dashboard:latest"
    echo "Dashboard image built and pushed!"
  else
    echo "Warning: dashboard/Dockerfile not found, skipping..."
  fi

  echo ""
else
  echo "Skipping image builds (--skip-build specified)"
  echo "Note: Images must already exist in registry at localhost:${REGISTRY_PORT}"
  echo ""
fi

# Create namespaces first (before installing components that use them)
echo "Creating namespaces..."
kubectl create namespace inferadb --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace fdb-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace local-path-storage --dry-run=client -o yaml | kubectl apply -f -

# Label namespaces for privileged workloads BEFORE deploying pods
# This prevents PodSecurity warnings during deployment
kubectl label namespace fdb-system pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace fdb-system pod-security.kubernetes.io/warn=privileged --overwrite
kubectl label namespace inferadb pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace inferadb pod-security.kubernetes.io/warn=privileged --overwrite
kubectl label namespace local-path-storage pod-security.kubernetes.io/enforce=privileged --overwrite
kubectl label namespace local-path-storage pod-security.kubernetes.io/warn=privileged --overwrite

# Install local-path-provisioner for PVC storage (Talos doesn't include a default StorageClass)
# Namespace already created and labeled above to avoid PodSecurity warnings
echo "Installing local-path-provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Install FDB operator from GitHub (no Helm chart published)
echo "Installing FoundationDB operator..."
FDB_OPERATOR_VERSION="v2.19.0"
FDB_RAW_URL="https://raw.githubusercontent.com/FoundationDB/fdb-kubernetes-operator/${FDB_OPERATOR_VERSION}"

# Install CRDs first
kubectl apply -f "${FDB_RAW_URL}/config/crd/bases/apps.foundationdb.org_foundationdbclusters.yaml"
kubectl apply -f "${FDB_RAW_URL}/config/crd/bases/apps.foundationdb.org_foundationdbbackups.yaml"
kubectl apply -f "${FDB_RAW_URL}/config/crd/bases/apps.foundationdb.org_foundationdbrestores.yaml"

# Wait for CRDs to be established
echo "Waiting for FoundationDB CRDs..."
kubectl wait --for=condition=established --timeout=60s crd/foundationdbclusters.apps.foundationdb.org

# Install RBAC (ClusterRole + Role from config/rbac/)
kubectl apply -f "${FDB_RAW_URL}/config/rbac/cluster_role.yaml"
kubectl apply -f "${FDB_RAW_URL}/config/rbac/role.yaml" -n fdb-system

# Install the operator deployment
# The upstream manager.yaml references serviceAccountName: fdb-kubernetes-operator-controller-manager
# but the ServiceAccount is named controller-manager (kustomize would add the prefix)
# Also configure it to watch all namespaces (default is single namespace mode)
curl -s "${FDB_RAW_URL}/config/deployment/manager.yaml" | \
  sed 's/serviceAccountName: fdb-kubernetes-operator-controller-manager/serviceAccountName: controller-manager/' | \
  sed '/WATCH_NAMESPACE/,/fieldPath:/d' | \
  kubectl apply -n fdb-system -f -

# Create role bindings with correct ClusterRole references
# Note: The ClusterRoles from config/rbac/ are named manager-role and manager-clusterrole
# (without the fdb-kubernetes-operator- prefix that kustomize would add)
# For global mode (no WATCH_NAMESPACE), we need ClusterRoleBindings for cluster-wide access
kubectl create clusterrolebinding fdb-operator-manager-role-global \
  --clusterrole=manager-role \
  --serviceaccount=fdb-system:controller-manager \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create clusterrolebinding fdb-operator-manager-clusterrolebinding \
  --clusterrole=manager-clusterrole \
  --serviceaccount=fdb-system:controller-manager \
  --dry-run=client -o yaml | kubectl apply -f -

# Create RBAC for FDB sidecar pods (they need to read/patch pods for annotations)
echo "Creating FDB sidecar RBAC..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: fdb-sidecar
  namespace: inferadb
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch", "patch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: fdb-sidecar
  namespace: inferadb
subjects:
- kind: ServiceAccount
  name: default
  namespace: inferadb
roleRef:
  kind: Role
  name: fdb-sidecar
  apiGroup: rbac.authorization.k8s.io
EOF

# Wait for operator to be ready with progress feedback
echo "Waiting for FDB operator to be ready..."
echo "(Init containers download FDB binaries, this may take a few minutes)"
WAIT_TIMEOUT=300
WAIT_INTERVAL=10
ELAPSED=0
while [ $ELAPSED -lt $WAIT_TIMEOUT ]; do
  # Show current pod status
  POD_STATUS=$(kubectl get pods -n fdb-system -o wide --no-headers 2>/dev/null || echo "Unable to get pod status")
  echo "  [$ELAPSED/${WAIT_TIMEOUT}s] $POD_STATUS"

  # Check if deployment is available
  if kubectl wait --for=condition=available --timeout=1s deployment/controller-manager -n fdb-system 2>/dev/null; then
    echo "FDB operator is ready!"
    break
  fi

  sleep $WAIT_INTERVAL
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $WAIT_TIMEOUT ]; then
  echo "ERROR: FDB operator did not become ready within ${WAIT_TIMEOUT}s"
  echo "Checking pod events for diagnostics..."
  kubectl describe pod -n fdb-system -l app=fdb-kubernetes-operator 2>/dev/null | grep -A 20 "Events:" || true
  kubectl logs -n fdb-system -l app=fdb-kubernetes-operator --tail=50 2>/dev/null || true
  exit 1
fi

# Apply apps (dev overlay) with registry IP substitution
echo "Deploying InferaDB applications..."

# Create a kustomization patch for the dev registry
# The registry is accessible from inside the cluster at ${REGISTRY_IP}:5000
cat > "${DEPLOY_DIR}/flux/apps/dev/registry-patch.yaml" <<EOF
# Auto-generated by dev-up.sh - patches images to use local registry
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-engine
  namespace: inferadb
spec:
  template:
    spec:
      containers:
        - name: inferadb-engine
          image: ${REGISTRY_IP}:5000/inferadb-engine:latest
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-control
  namespace: inferadb
spec:
  template:
    spec:
      containers:
        - name: inferadb-control
          image: ${REGISTRY_IP}:5000/inferadb-control:latest
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-dashboard
  namespace: inferadb
spec:
  template:
    spec:
      containers:
        - name: inferadb-dashboard
          image: ${REGISTRY_IP}:5000/inferadb-dashboard:latest
EOF

# Note: registry-patch.yaml is referenced in kustomization.yaml patches section
# The file is generated above with the current registry IP

kubectl apply -k "${DEPLOY_DIR}/flux/apps/dev"

echo ""
echo "Applications deployed!"
echo ""
echo "Note: It may take a few minutes for all pods to be ready."
echo "Monitor progress with: kubectl get pods -n inferadb -w"

echo ""
echo "=== Development environment ready! ==="
echo ""
echo "Cluster context: ${KUBE_CONTEXT}"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -A                    # List all pods"
echo "  kubectl get pods -n inferadb           # List InferaDB pods"
echo "  kubectl get nodes                      # List nodes"
echo "  talosctl dashboard --nodes 10.5.0.2    # Talos dashboard"
echo ""
echo "Port forwarding (run in separate terminals):"
echo "  kubectl port-forward -n inferadb svc/inferadb-engine 8080:8080"
echo "  kubectl port-forward -n inferadb svc/inferadb-control 9090:9090"
echo "  kubectl port-forward -n inferadb svc/inferadb-dashboard 3000:3000"
echo ""
echo "To destroy this cluster, run:"
echo "  ./scripts/dev-down.sh"
echo ""
