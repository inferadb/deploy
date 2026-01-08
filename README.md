<div align="center">
    <p><a href="https://inferadb.com"><img src=".github/inferadb.png" width="100" /></a></p>
    <h1>InferaDB Deployment</h1>
    <p>
        <a href="https://discord.gg/inferadb"><img src="https://img.shields.io/badge/Discord-Join%20us-5865F2?logo=discord&logoColor=white" alt="Discord" /></a>
        <a href="#license"><img src="https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg" alt="License" /></a>
    </p>
    <p>GitOps deployment for multi-region, multi-cloud Kubernetes</p>
</div>

> [!IMPORTANT]
> Under active development. Not production-ready.

## Architecture Overview

- **OS**: Talos Linux (immutable, API-driven)
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

Use the [InferaDB CLI](https://github.com/inferadb/cli) for local development:

```bash
# Create local cluster and deploy InferaDB stack
inferadb dev start

# Show cluster status
inferadb dev status

# Tear down cluster
inferadb dev stop --destroy
```

The dev environment deploys:

- **FoundationDB**: Single-node cluster
- **Engine**: Authorization policy engine
- **Control**: Control plane API
- **Dashboard**: Web console

Access services:

```bash
kubectl port-forward -n inferadb svc/inferadb-engine 8080:8080
kubectl port-forward -n inferadb svc/inferadb-control 9090:9090
kubectl port-forward -n inferadb svc/inferadb-dashboard 3000:3000
```

### Staging/Production Deployment

```bash
# Bootstrap a cluster
./scripts/bootstrap-cluster.sh <environment> <region> <provider>

# Example: staging NYC1 on AWS
./scripts/bootstrap-cluster.sh staging nyc1 aws
```

## Environments

| Environment | Regions              | Purpose                    |
| ----------- | -------------------- | -------------------------- |
| Development | Local (Docker)       | Development and testing    |
| Staging     | NYC1 + monthly drills| Pre-production validation  |
| Production  | NYC1, SFO1           | Live workloads             |

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

- Pod Security Standards (namespace-level)
- Cilium NetworkPolicies (default deny)
- Image signing via Kyverno
- WireGuard pod-to-pod encryption
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

Enable git hooks:

```bash
git config core.hooksPath .githooks
```

Required tools (via `.mise.toml` or manual install):

- `terraform` - formatting
- `yamllint` - YAML linting (`pip install yamllint`)
- `shellcheck` - shell linting

## Contributing

All changes require PR review. CI runs on push/PR:

- **Terraform**: Format and validate checks
- **Kubernetes**: YAML lint and Kustomize build validation
- **Security**: Trivy, Checkov, and KICS scans

## Community

Join us on [Discord](https://discord.gg/inferadb) for questions, discussions, and contributions.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE).
