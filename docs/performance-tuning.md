# Performance Tuning Guide

This guide covers performance optimization for InferaDB deployments.

## Overview

InferaDB performance depends on three main components:

1. **Engine** - Authorization decision latency
2. **Control** - Policy management API response time
3. **FoundationDB** - Underlying data store performance

## Performance Targets

| Metric                      | Target         | Critical      |
| --------------------------- | -------------- | ------------- |
| Authorization latency (p50) | < 1ms          | < 5ms         |
| Authorization latency (p99) | < 5ms          | < 20ms        |
| Throughput per Engine pod   | > 10,000 req/s | > 5,000 req/s |
| Cache hit rate              | > 95%          | > 80%         |

## Engine Tuning

### Worker Threads

Configure worker threads based on available CPU cores:

```yaml
# engine/helm/values.yaml
config:
  threads: 4 # Match CPU limit
```

**Guideline**: Set `threads` to match your container's CPU limit.

```yaml
resources:
  limits:
    cpu: 4000m # 4 cores
config:
  threads: 4 # Match CPU limit
```

### Cache Configuration

The Engine caches authorization decisions and JWKS keys:

```yaml
config:
  cache:
    enabled: true
    capacity: 10000 # Max entries
    ttl: 300 # TTL in seconds

  token:
    cacheTtl: 300 # JWKS cache TTL
```

**Tuning guidelines:**

| Workload                   | Capacity | TTL  |
| -------------------------- | -------- | ---- |
| Low (< 1k unique policies) | 5,000    | 600s |
| Medium (1k-10k policies)   | 10,000   | 300s |
| High (> 10k policies)      | 50,000   | 180s |

### Connection Pooling

For high-throughput deployments, tune FDB connection settings:

```yaml
config:
  foundationdb:
    clusterFile: "/etc/foundationdb/fdb.cluster"
    # Connection pool settings (if supported)
    maxConnections: 100
    connectionTimeout: 5000
```

### Horizontal Scaling

Scale Engine pods based on request rate:

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70

  # Custom metrics scaling (recommended)
  customMetrics:
    - type: Pods
      pods:
        metric:
          name: inferadb_requests_per_second
        target:
          type: AverageValue
          averageValue: "5000" # Scale at 5k req/s per pod
```

## FoundationDB Tuning

### Storage Engine

Use `ssd-2` for production:

```yaml
# FDB cluster configuration
databaseConfiguration:
  storage_engine: ssd-2 # Best for SSDs
  # storage_engine: ssd-redwood-1  # Alternative with better compression
```

### Process Counts

Scale based on workload:

| Workload               | Storage | Log | Stateless |
| ---------------------- | ------- | --- | --------- |
| Small (< 10k req/s)    | 3       | 3   | 3         |
| Medium (10k-50k req/s) | 5       | 5   | 5         |
| Large (> 50k req/s)    | 9+      | 9+  | 9+        |

### Memory Configuration

FDB processes benefit from memory for caching:

```yaml
# FDB pod resources
resources:
  requests:
    memory: 8Gi
  limits:
    memory: 16Gi
```

### Disk Configuration

Use local NVMe storage for best performance:

```yaml
# Node selector for NVMe instances
nodeSelector:
  node.kubernetes.io/instance-type: i3.xlarge

# Or use local volume provisioner
volumeClaimTemplates:
  - metadata:
      name: fdb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: local-nvme
      resources:
        requests:
          storage: 500Gi
```

### Commit Proxy Tuning

For write-heavy workloads, increase commit proxies:

```yaml
databaseConfiguration:
  commit_proxies: 5 # Default is 3
  grv_proxies: 3 # Read version proxies
```

## Network Tuning

### Pod Anti-Affinity

Spread pods across nodes for better fault tolerance and reduced network hops:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: inferadb-engine
          topologyKey: kubernetes.io/hostname
```

### Topology Spread

Distribute across availability zones:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: inferadb-engine
```

### Service Mesh Considerations

If using a service mesh (Istio, Linkerd):

1. **Exclude FDB ports** from mesh to avoid latency overhead
2. **Use mTLS termination** at the sidecar, not the application
3. **Monitor sidecar CPU** - sidecars add ~5-10ms latency

```yaml
# Istio port exclusion
annotations:
  traffic.sidecar.istio.io/excludeOutboundPorts: "4500,4501"
```

## Multi-Region Tuning

### Local Read Preference

Configure Engine to prefer local FDB replicas:

```yaml
config:
  foundationdb:
    # Prefer reads from local datacenter
    datacenter: "us-west-1"
```

### Cross-Region Latency

For Tailscale multi-region setups:

1. **Use DERP relays** only as fallback
2. **Enable direct connections** between regions
3. **Monitor `tailscale ping`** latency between pods

```bash
# Check inter-region latency
kubectl exec -it inferadb-engine-0 -c tailscale -- tailscale ping inferadb-engine-0.eu-west-1
```

### Cache Invalidation Tuning

For multi-region, tune cache invalidation:

```yaml
config:
  mesh:
    timeout: 5000 # Increase for cross-region
    cacheTtl: 300 # Balance freshness vs. performance
```

## Profiling and Debugging

### Enable Debug Logging

```yaml
extraEnv:
  - name: RUST_LOG
    value: "info,inferadb_engine=debug,inferadb_fdb=debug"
```

### Prometheus Metrics

Key metrics to monitor:

```promql
# Authorization latency histogram
histogram_quantile(0.99, rate(inferadb_authorization_duration_seconds_bucket[5m]))

# Request throughput
rate(inferadb_requests_total[5m])

# Cache effectiveness
inferadb_cache_hits_total / (inferadb_cache_hits_total + inferadb_cache_misses_total)

# FDB latency
histogram_quantile(0.99, rate(fdb_transaction_duration_seconds_bucket[5m]))
```

### Tracing

Enable distributed tracing for latency analysis:

```yaml
config:
  tracing:
    enabled: true
    endpoint: "http://jaeger-collector:14268/api/traces"
    sampleRate: 0.01 # 1% sampling in production
```

## Benchmarking

### Load Testing

Use the included load test tool:

```bash
cd engine/loadtests

# Run baseline test
k6 run --vus 100 --duration 5m baseline.js

# Run stress test
k6 run --vus 1000 --duration 10m stress.js
```

### Baseline Expectations

On `m6i.xlarge` (4 vCPU, 16GB RAM):

| Scenario                | Expected Throughput | Expected p99 Latency |
| ----------------------- | ------------------- | -------------------- |
| Cache hit               | 15,000 req/s        | < 1ms                |
| Cache miss (local FDB)  | 8,000 req/s         | < 3ms                |
| Cache miss (remote FDB) | 3,000 req/s         | < 15ms               |

## Common Performance Issues

### High Latency

**Symptoms**: p99 latency > 20ms

**Checks**:

1. Cache hit rate (should be > 90%)
2. FDB transaction latency
3. Network latency between pods

```bash
# Check FDB latency
kubectl exec -it inferadb-fdb-storage-0 -c foundationdb -- fdbcli --exec "status details"
```

### Low Throughput

**Symptoms**: < 5,000 req/s per pod

**Checks**:

1. CPU utilization (should be < 80%)
2. Worker thread count
3. Connection pool exhaustion

```bash
# Check CPU usage
kubectl top pods -n inferadb -l app.kubernetes.io/name=inferadb-engine
```

### Memory Pressure

**Symptoms**: OOMKilled pods, high memory usage

**Checks**:

1. Cache capacity too high
2. Memory leaks (monitor over time)
3. Large policy documents

```bash
# Check memory usage
kubectl top pods -n inferadb --containers
```

## References

- [FoundationDB Performance](https://apple.github.io/foundationdb/performance.html)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [InferaDB Helm Chart](../../engine/helm/README.md)
