# InferaDB Deployment Infrastructure

This directory contains the deployment infrastructure for InferaDB, supporting multi-environment,
multi-region, and multi-provider deployments using GitOps principles.

## Architecture Overview

- **OS**: Talos Linux (immutable, API-driven Kubernetes)
- **Orchestration**: Kubernetes
- **GitOps**: Flux CD
- **IaC**: Terraform + OpenTofu
- **CNI**: Cilium (with WireGuard encryption)
- **Networking**: Tailscale mesh
- **Secret Management**: External Secrets Operator + SOPS

## Directory Structure

```text
deploy/
├── terraform/          # Infrastructure provisioning
│   ├── modules/        # Reusable Terraform modules
│   ├── environments/   # Environment-specific configs (dev, staging, production)
│   └── regions/        # Regional cluster definitions
├── flux/               # GitOps configurations
│   ├── clusters/       # Cluster-specific Flux configs
│   ├── infrastructure/ # Cluster infrastructure (CNI, operators, etc.)
│   └── apps/           # Application deployments
├── talos/              # Talos Linux configurations
├── policies/           # Kyverno and network policies
├── scripts/            # Deployment automation scripts
├── runbooks/           # Operational runbooks
├── alerts/             # Prometheus alerting rules
├── slos/               # Service Level Objectives
└── docs/               # Documentation and ADRs
```

## Quick Start

### Local Development

Use the InferaDB CLI for local development:

```bash
# Create local Talos cluster and deploy full InferaDB stack
inferadb dev start

# Show cluster status
inferadb dev status

# Tear down local cluster
inferadb dev stop --destroy
```

The dev environment deploys:

- **FoundationDB**: Single-node cluster for development
- **Engine**: Authorization policy decision engine
- **Control**: Control plane API
- **Dashboard**: Web console

Access services via port forwarding:

```bash
kubectl port-forward -n inferadb svc/inferadb-engine 8080:8080
kubectl port-forward -n inferadb svc/inferadb-control 9090:9090
kubectl port-forward -n inferadb svc/inferadb-dashboard 3000:3000
```

### Staging/Production Deployment

```bash
# Bootstrap a new cluster
./scripts/bootstrap-cluster.sh <environment> <region> <provider>

# Example: Bootstrap staging NYC1 on AWS
./scripts/bootstrap-cluster.sh staging nyc1 aws
```

## Environments

| Environment | Regions              | Purpose                           |
| ----------- | -------------------- | --------------------------------- |
| Development | Local (Docker)       | Local development and testing     |
| Staging     | NYC1 + monthly drills| Pre-production validation         |
| Production  | NYC1, SFO1           | Production workloads              |

## Key Components

### Terraform Modules

- `talos-cluster`: Abstract Talos K8s cluster provisioning
- `provider-aws`: AWS-specific resources (VPC, EC2, etc.)
- `provider-gcp`: GCP-specific resources
- `provider-digitalocean`: DigitalOcean-specific resources
- `fdb-backup`: FoundationDB backup infrastructure
- `dns`: Multi-provider DNS management

### Flux Kustomizations

- `infrastructure/base`: Shared controllers and operators
- `apps/base`: Application deployments (engine, control, dashboard)

## Security

- Pod Security Standards enforced at namespace level
- Cilium NetworkPolicies with default deny
- Image signing verification via Kyverno
- WireGuard encryption for all pod-to-pod traffic
- Trivy vulnerability scanning

## Documentation

- [Getting Started](docs/getting-started.md)
- [Adding Regions](docs/adding-regions.md)
- [Disaster Recovery](docs/disaster-recovery.md)
- [Security Model](docs/security-model.md)
- [Cost Estimation](docs/cost-estimation.md)

## Runbooks

- [FDB Cluster Recovery](runbooks/fdb-cluster-recovery.md)
- [Node Replacement](runbooks/node-replacement.md)
- [Full Region Failover](runbooks/full-region-failover.md)
- [Break-Glass Procedures](runbooks/break-glass-procedures.md)

## Development Setup

Enable git hooks for local validation:

```bash
git config core.hooksPath .githooks
```

Required tools (install via `.mise.toml` or manually):

- `terraform` - Terraform formatting
- `yamllint` - YAML linting (`pip install yamllint`)
- `shellcheck` - Shell script linting
- `gitleaks` - Secret detection

## Contributing

All changes require PR review. CI runs automatically on push/PR:

- **Terraform**: Format and validate checks
- **Kubernetes**: YAML lint and Kustomize build validation
- **Security**: Trivy, Checkov, KICS, and Gitleaks scans

See [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md) for the full architecture specification.
