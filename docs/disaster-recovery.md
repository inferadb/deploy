# Disaster Recovery Guide

This guide covers disaster recovery procedures for InferaDB deployments using Ledger Raft replication.

## Overview

InferaDB's disaster recovery is built on Ledger's native Raft replication. When properly configured, the system provides:

- **RPO (Recovery Point Objective)**: Near-zero (synchronous replication)
- **RTO (Recovery Time Objective)**: < 60 seconds for automatic failover

## Architecture

```mermaid
flowchart TB
    subgraph primary["Primary Region (Active)"]
        ledger1[Ledger Cluster]
        engine1[Engine Pods]
        control1[Control Pods]
    end

    subgraph dr["DR Region (Standby)"]
        ledger2[Ledger Cluster]
        engine2[Engine Pods]
        control2[Control Pods]
    end

    ledger1 -->|"Raft Replication"| ledger2

    subgraph failover["On Primary Failure"]
        ledger2 -->|"Elect New Leader"| active[Accept Writes]
    end
```

## Pre-Requisites

Before a disaster occurs, ensure:

1. **Multi-region Ledger deployed** - See [ledger-multi-region.md](./ledger-multi-region.md)
2. **Tailscale mesh configured** - See [tailscale-multi-region.md](./tailscale-multi-region.md)
3. **Monitoring in place** - Alerts for replication lag and availability
4. **Runbooks documented** - Team knows recovery procedures

## Failure Scenarios

### Scenario 1: Single Pod Failure

**Impact**: Minimal - Kubernetes handles automatically

**Recovery**: Automatic pod restart via Deployment/StatefulSet

```bash
# Verify pod recovery
kubectl get pods -n inferadb -w
```

### Scenario 2: Single Node Failure

**Impact**: Temporary capacity reduction

**Recovery**:

1. Kubernetes reschedules pods to healthy nodes
2. Ledger redistributes data automatically

```bash
# Check Ledger status
kubectl exec -it inferadb-ledger-0 -n inferadb -- grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
```

### Scenario 3: Availability Zone Failure

**Impact**: Reduced redundancy within region

**Recovery**:

1. Pods reschedule to surviving AZs
2. Ledger maintains quorum if majority survives

```bash
# Check node distribution
kubectl get pods -n inferadb -o wide
```

### Scenario 4: Full Region Failure

**Impact**: Primary region unavailable

**Recovery**: DR region promotion (see below)

## DR Region Promotion

### Automatic Failover

Ledger Raft replication handles most failures automatically:

1. Primary region becomes unavailable
2. Remaining nodes detect leader loss
3. DR region elects new leader (typically < 10 seconds)
4. Applications reconnect to DR endpoints

**Monitor for automatic failover:**

```bash
# Watch Ledger status in DR region
kubectl exec -it inferadb-ledger-0 -n inferadb \
  --context eks-dr -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/GetClusterStatus
```

### Manual Failover

Use manual failover when:

- Automatic failover hasn't triggered
- You need to force promotion for testing
- Primary is partially available but degraded

```bash
# Force leader election in DR region
kubectl exec -it inferadb-ledger-0 -n inferadb \
  --context eks-dr -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/ForceLeaderElection
```

### Post-Failover Steps

1. **Verify DR is primary:**

   ```bash
   kubectl exec -it inferadb-ledger-0 -n inferadb \
     --context eks-dr -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/GetClusterStatus
   # Should show healthy leader status
   ```

2. **Update DNS/Load Balancer** (if not automatic):

   ```bash
   # Update Route53 health checks or similar
   aws route53 update-health-check --health-check-id <id> --regions eu-west-1
   ```

3. **Notify stakeholders** via incident management system

4. **Document the incident** for post-mortem

## Failback Procedure

After the original primary recovers:

### Step 1: Verify Original Primary Health

```bash
# Check infrastructure is healthy
kubectl get nodes --context eks-primary
kubectl get pods -n inferadb --context eks-primary
```

### Step 2: Re-sync Data

The original primary automatically re-syncs from current leader:

```bash
# Monitor sync progress
kubectl exec -it inferadb-ledger-0 -n inferadb \
  --context eks-primary -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/GetClusterStatus
```

Wait for "Fully replicated" status.

### Step 3: Optional Promotion Back

If you want the original region as primary:

```bash
# Trigger leader transfer to original region
kubectl exec -it inferadb-ledger-0 -n inferadb \
  --context eks-primary -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/RequestLeaderTransfer
```

**Note**: Only do this during a maintenance window.

## Testing DR

### Monthly DR Drills

1. **Schedule maintenance window**
2. **Notify stakeholders**
3. **Simulate primary failure:**

   ```bash
   # Scale down primary Ledger
   kubectl scale statefulset inferadb-ledger --replicas=0 \
     -n inferadb --context eks-primary
   ```

4. **Verify DR promotion** (should happen within 60s)
5. **Test application connectivity** to DR region
6. **Restore primary:**

   ```bash
   kubectl scale statefulset inferadb-ledger --replicas=3 \
     -n inferadb --context eks-primary
   ```

7. **Document results** in `deploy/dr-drill-results/`

### Automated DR Testing

Consider implementing automated DR testing in CI/CD:

```yaml
# Example GitHub Actions workflow
name: DR Drill
on:
  schedule:
    - cron: "0 3 1 * *" # Monthly at 3 AM

jobs:
  dr-drill:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger DR failover
        run: ./scripts/dr-drill.sh
      - name: Verify DR health
        run: ./scripts/verify-dr-health.sh
      - name: Restore primary
        run: ./scripts/restore-primary.sh
```

## Monitoring and Alerts

### Key Metrics

| Metric                           | Alert Threshold | Action                   |
| -------------------------------- | --------------- | ------------------------ |
| `ledger_raft_leader`             | == 0            | Page on-call             |
| `ledger_replication_lag_seconds` | > 5s            | Investigate network      |
| `ledger_raft_peers_connected`    | < quorum        | Check peer health        |

### Alert Examples

```yaml
# Prometheus alert rules
groups:
  - name: inferadb-dr
    rules:
      - alert: LedgerReplicationLagHigh
        expr: ledger_replication_lag_seconds > 5
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Ledger replication lag is high"

      - alert: LedgerNoLeader
        expr: ledger_raft_leader == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "Ledger cluster has no leader - DR may be needed"
```

## Backup and Restore

While Ledger Raft replication handles real-time replication, maintain backups for:

- Point-in-time recovery
- Corruption recovery
- Compliance requirements

### Ledger Backup

```bash
# Trigger snapshot backup
kubectl exec -it inferadb-ledger-0 -n inferadb -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/CreateSnapshot

# Copy snapshot to external storage
kubectl cp inferadb-ledger-0:/var/lib/ledger/snapshots/ ./backup/
```

### Restore from Backup

```bash
# Restore snapshot to new cluster
kubectl cp ./backup/ inferadb-ledger-0:/var/lib/ledger/snapshots/
kubectl exec -it inferadb-ledger-0 -n inferadb -- grpcurl -plaintext localhost:50051 inferadb.ledger.v1.Admin/RestoreFromSnapshot
```

## References

- [InferaDB Multi-Region Setup](./ledger-multi-region.md)
- [Operational Runbooks](../../deploy/runbooks/)
