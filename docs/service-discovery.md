# Service Discovery in InferaDB

## Overview

InferaDB supports dynamic service discovery for production deployments with multiple instances.

## Discovery Modes

### Static (Development)

- Manually configured URLs
- No external dependencies
- Best for: Local development, simple deployments

### Kubernetes Service (Production)

- Automatic pod discovery via k8s Endpoints API
- Health-aware routing
- Best for: Production Kubernetes deployments

## Configuration

### Engine - Control Discovery

Configure via Helm values or environment variables:

```yaml
# engine/helm/values.yaml
discovery:
  mode: "kubernetes" # Options: "none", "kubernetes", "tailscale"
  cacheTtl: 300
  control:
    serviceName: "inferadb-control"
    namespace: "inferadb"
    port: 9092 # Control mesh API port
```

Or via environment variables:

```bash
INFERADB__AUTH__DISCOVERY__MODE=kubernetes
INFERADB__AUTH__DISCOVERY__CONTROL__SERVICE_NAME=inferadb-control
INFERADB__AUTH__DISCOVERY__CONTROL__NAMESPACE=inferadb
```

### Control - Engine Discovery

Configure via Helm values or config file:

```yaml
# control/helm/values.yaml
discovery:
  mode: "kubernetes"
  cacheTtl: 30
  engine:
    serviceName: "inferadb-engine"
    namespace: "inferadb"
    port: 8080
    labelSelector: "app.kubernetes.io/name=inferadb-engine"
```

Or via environment variables:

```bash
INFERADB_CTRL__CACHE_INVALIDATION__DISCOVERY__MODE__TYPE=kubernetes
INFERADB_CTRL__CACHE_INVALIDATION__DISCOVERY__CACHE_TTL=30
```

> **Note**: Both Engine and Control now have Helm charts available:
>
> - Engine: `engine/helm/`
> - Control: `control/helm/`

## RBAC Requirements

Service discovery requires k8s API access. Ensure ServiceAccounts have proper permissions:

```bash
# Apply RBAC configuration
kubectl apply -f engine/k8s/rbac.yaml
kubectl apply -f control/k8s/rbac.yaml
```

## Monitoring

Key metrics to monitor:

- `inferadb_discovery_operations_total` - Discovery success/failure
- `inferadb_lb_endpoint_health` - Endpoint health status
- `inferadb_discovery_cache_hits_total` - Cache effectiveness

## Troubleshooting

### Discovery Fails with Permission Denied

- Check ServiceAccount is configured
- Verify RBAC Role has endpoints/services access
- Check namespace matches service location

### Endpoints Not Discovered

- Verify service exists: `kubectl get svc -n inferadb`
- Check pods are ready: `kubectl get pods -n inferadb`
- Review logs for discovery errors
