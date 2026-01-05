# Migrating to Service Discovery

## Overview

This guide covers migrating from static configuration to dynamic service discovery.

## Prerequisites

- Kubernetes 1.28+
- Helm 3.0+
- kubectl access to cluster

## Migration Steps

### 1. Deploy Using Helm (Recommended)

Both Engine and Control have Helm charts that include RBAC configuration:

```bash
# Deploy Engine with discovery enabled
helm install inferadb-engine ./engine/helm \
  --namespace inferadb \
  --create-namespace \
  --set discovery.mode=kubernetes

# Deploy Control with discovery enabled
helm install inferadb-control ./control/helm \
  --namespace inferadb \
  --set discovery.mode=kubernetes
```

### 1b. Alternative: Manual RBAC

If not using Helm, apply RBAC manually:

```bash
kubectl apply -f engine/k8s/rbac.yaml
kubectl apply -f control/k8s/rbac.yaml
```

### 2. Update Configuration

**Option A: Helm (Recommended)**

```bash
# Update values.yaml
helm upgrade inferadb-engine ./engine/helm \
  --set discovery.mode=kubernetes \
  --set discovery.control.serviceName=inferadb-control
```

**Option B: Environment Variables**

```bash
# Update deployment
kubectl set env deployment/inferadb-engine \
  INFERADB__AUTH__DISCOVERY__MODE=kubernetes \
  INFERADB__AUTH__DISCOVERY__CONTROL__SERVICE_NAME=inferadb-control
```

### 3. Verify Discovery

Check logs for successful discovery:

```bash
kubectl logs -f deployment/inferadb-engine | grep discovery
# Expected: "Discovered k8s endpoints: count=3"
```

### 4. Monitor Metrics

```bash
# Check discovery health
kubectl port-forward svc/inferadb-engine 8080:8080
curl localhost:8080/metrics | grep discovery
```

## Rollback

If issues occur, revert to static mode:

```bash
helm upgrade inferadb-engine ./engine/helm \
  --set discovery.mode=none \
  --set config.mesh.url=http://inferadb-control:9092
```

> **Note**: When `discovery.mode=none`, configure the Control URL directly via `config.mesh.url`.

## Backward Compatibility

Static configuration still works - no breaking changes.
