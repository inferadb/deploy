# Local Kubernetes Testing Guide

This guide covers testing InferaDB's Kubernetes service discovery features locally using **kind** (Kubernetes in Docker).

## Prerequisites

```bash
# Install kind (Kubernetes in Docker)
brew install kind

# Install kubectl
brew install kubectl

# Install helm
brew install helm

# Verify Docker is running
docker ps
```

## Quick Start

### 1. Create Local Kubernetes Cluster

```bash
# Create a kind cluster named "inferadb-local"
kind create cluster --name inferadb-local --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# Verify cluster is running
kubectl cluster-info --context kind-inferadb-local
kubectl get nodes
```

### 2. Build and Load Docker Images

```bash
# Build engine image
cd engine
docker build -t inferadb-engine:local .

# Build control image
cd ../control
docker build -t inferadb-control:local .

# Load images into kind cluster
kind load docker-image inferadb-engine:local --name inferadb-local
kind load docker-image inferadb-control:local --name inferadb-local
```

### 3. Deploy FoundationDB

```bash
# Add FoundationDB operator
kubectl create namespace inferadb
kubectl apply -f https://raw.githubusercontent.com/FoundationDB/fdb-kubernetes-operator/main/config/crd/bases/apps.foundationdb.org_foundationdbclusters.yaml

# Deploy a simple FDB cluster for testing
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: foundationdb-cluster-file
  namespace: inferadb
data:
  fdb.cluster: "docker:docker@127.0.0.1:4500"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: foundationdb
  namespace: inferadb
spec:
  serviceName: foundationdb
  replicas: 1
  selector:
    matchLabels:
      app: foundationdb
  template:
    metadata:
      labels:
        app: foundationdb
    spec:
      containers:
      - name: foundationdb
        image: foundationdb/foundationdb:7.1.38
        ports:
        - containerPort: 4500
---
apiVersion: v1
kind: Service
metadata:
  name: foundationdb-cluster
  namespace: inferadb
spec:
  selector:
    app: foundationdb
  ports:
  - port: 4500
    targetPort: 4500
EOF
```

### 4. Deploy RBAC Resources

```bash
# Apply RBAC for both Engine and Control
kubectl apply -f engine/k8s/rbac.yaml -n inferadb
kubectl apply -f control/k8s/rbac.yaml -n inferadb
```

### 5. Deploy Control

```bash
# Create control secrets
kubectl create secret generic inferadb-control-secrets \
  --namespace inferadb \
  --from-literal=INFERADB_CTRL__DATABASE__FDB_CLUSTER_FILE=/etc/foundationdb/fdb.cluster

# Deploy Control
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: inferadb-control-config
  namespace: inferadb
data:
  config.yaml: |
    http:
      host: "0.0.0.0"
      port: 9090
    storage:
      backend: "foundationdb"
      fdb_cluster_file: "/etc/foundationdb/fdb.cluster"
    cache_invalidation:
      http_endpoints: []
      discovery:
        type: "kubernetes"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-control
  namespace: inferadb
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inferadb-control
  template:
    metadata:
      labels:
        app: inferadb-control
    spec:
      serviceAccountName: inferadb-control
      containers:
      - name: control
        image: inferadb-control:local
        imagePullPolicy: Never
        ports:
        - containerPort: 9090
        env:
        - name: RUST_LOG
          value: "info,inferadb_control_core=debug"
        volumeMounts:
        - name: config
          mountPath: /etc/inferadb
        - name: fdb-cluster-file
          mountPath: /etc/foundationdb
      volumes:
      - name: config
        configMap:
          name: inferadb-control-config
      - name: fdb-cluster-file
        configMap:
          name: foundationdb-cluster-file
---
apiVersion: v1
kind: Service
metadata:
  name: inferadb-control
  namespace: inferadb
spec:
  selector:
    app: inferadb-control
  ports:
  - port: 9090
    targetPort: 9090
EOF
```

### 6. Deploy Engine with Service Discovery

```bash
# Deploy Engine with Kubernetes discovery enabled
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-engine
  namespace: inferadb
spec:
  replicas: 3
  selector:
    matchLabels:
      app: inferadb-engine
  template:
    metadata:
      labels:
        app: inferadb-engine
    spec:
      serviceAccountName: inferadb-engine
      containers:
      - name: inferadb
        image: inferadb-engine:local
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        env:
        - name: RUST_LOG
          value: "info,inferadb_discovery=debug,inferadb_auth=debug"
        - name: INFERADB__ENGINE__HOST
          value: "0.0.0.0"
        - name: INFERADB__ENGINE__PORT
          value: "8080"
        - name: INFERADB__AUTH__DISCOVERY__MODE__TYPE
          value: "kubernetes"
        - name: INFERADB__AUTH__DISCOVERY__CACHE_TTL_SECONDS
          value: "30"
        - name: INFERADB__AUTH__CONTROL_URL
          value: "http://inferadb-control.inferadb.svc.cluster.local:9090"
---
apiVersion: v1
kind: Service
metadata:
  name: inferadb-engine
  namespace: inferadb
spec:
  selector:
    app: inferadb-engine
  ports:
  - port: 8080
    targetPort: 8080
EOF
```

## Testing Service Discovery

### Verify Kubernetes Discovery

```bash
# Watch engine logs for discovery messages
kubectl logs -f deployment/inferadb-engine -n inferadb | grep -i discovery

# Expected log output:
# "Discovered k8s endpoints: count=2"
# "Using cached endpoints"
```

### Test Control Discovery

```bash
# Trigger a webhook from Control
kubectl exec -n inferadb deployment/inferadb-control -- \
  curl -X POST http://localhost:9090/v1/organizations/123/vaults/456

# Check control logs for endpoint discovery
kubectl logs -f deployment/inferadb-control -n inferadb | grep -i discovery

# Expected output:
# "Discovered Kubernetes endpoints"
# "Discovered engine endpoints: count=3"
```

### Verify Endpoints API Access

```bash
# Check if engine can query k8s endpoints
kubectl exec -n inferadb deployment/inferadb-engine -- \
  curl -s http://kubernetes.default.svc/api/v1/namespaces/inferadb/endpoints/inferadb-control \
  --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Should return JSON with pod IPs
```

### Scale and Observe

```bash
# Scale Control and watch engine discover new endpoints
kubectl scale deployment/inferadb-control --replicas=4 -n inferadb

# Wait 30 seconds for cache expiry, then check engine logs
sleep 30
kubectl logs deployment/inferadb-engine -n inferadb --tail=20 | grep discovered

# Scale down
kubectl scale deployment/inferadb-control --replicas=2 -n inferadb
```

## Testing Tailscale (Advanced)

For Tailscale testing, you'll need a Tailscale account and auth key:

### 1. Get Tailscale Auth Key

```bash
# Visit https://login.tailscale.com/admin/settings/keys
# Generate an auth key with "Reusable" and "Ephemeral" options
```

### 2. Create Tailscale Secret

```bash
kubectl create secret generic tailscale-auth \
  --namespace inferadb \
  --from-literal=authkey=tskey-auth-YOUR-KEY-HERE
```

### 3. Deploy with Tailscale Sidecar

```bash
# Apply Tailscale sidecar manifests
kubectl apply -f engine/k8s/tailscale-sidecar.yaml -n inferadb
kubectl apply -f control/k8s/tailscale-sidecar.yaml -n inferadb
```

### 4. Configure Multi-Region Discovery

For true multi-region testing, you'd need:

- Multiple kind clusters or cloud k8s clusters
- Tailscale running in each cluster
- Configure RemoteCluster entries pointing to other regions

See [tailscale-multi-region.md](tailscale-multi-region.md) for full production setup.

## Monitoring and Debugging

### Check Prometheus Metrics

```bash
# Port-forward to engine metrics endpoint
kubectl port-forward -n inferadb deployment/inferadb-engine 8080:8080

# Query discovery metrics
curl http://localhost:8080/metrics | grep -E "inferadb_(discovery|lb_)"
```

Key metrics to watch:

- `inferadb_discovery_operations_total{result="success"}` - Should increment
- `inferadb_discovery_cache_hits_total` - Cache effectiveness
- `inferadb_lb_endpoint_health` - Endpoint health status
- `inferadb_discovered_endpoints` - Current endpoint count

### Common Issues

#### Discovery Fails with "403 Forbidden"

**Problem**: ServiceAccount doesn't have Endpoints read permission

**Solution**:

```bash
# Verify RBAC is applied
kubectl get role inferadb-engine -n inferadb
kubectl get rolebinding inferadb-engine -n inferadb

# Re-apply RBAC
kubectl apply -f engine/k8s/rbac.yaml -n inferadb
```

#### No Endpoints Discovered

**Problem**: Service or pods don't exist yet

**Solution**:

```bash
# Check service exists
kubectl get svc inferadb-control -n inferadb

# Check pods are ready
kubectl get pods -n inferadb -l app=inferadb-control

# Check endpoints manually
kubectl get endpoints inferadb-control -n inferadb
```

#### Cache Not Working

**Problem**: Cache TTL too short or discovery failing

**Solution**:

```bash
# Increase cache TTL
kubectl set env deployment/inferadb-engine \
  INFERADB__AUTH__DISCOVERY__CACHE_TTL_SECONDS=300 \
  -n inferadb

# Check logs for cache hits
kubectl logs deployment/inferadb-engine -n inferadb | grep "cache hit"
```

## Cleanup

```bash
# Delete the kind cluster
kind delete cluster --name inferadb-local

# Or just delete the namespace
kubectl delete namespace inferadb
```

## Next Steps

- Review logs to verify discovery is working
- Test failover by deleting pods
- Monitor metrics in production
- See [service-discovery.md](service-discovery.md) for production deployment
