# InferaDB Deployment Infrastructure

## Purpose
Multi-environment, multi-region, multi-provider deployment infrastructure for InferaDB using GitOps principles.

## Tech Stack
- **OS**: Talos Linux (immutable, API-driven Kubernetes)
- **Orchestration**: Kubernetes
- **IaC**: Terraform / OpenTofu
- **GitOps**: Flux CD
- **CNI**: Cilium (with WireGuard encryption)
- **Networking**: Tailscale mesh
- **Secret Management**: External Secrets Operator + SOPS
- **Policy Engine**: Kyverno

## Languages
- Terraform (HCL)
- YAML (Kubernetes manifests, Flux, Helm)
- Shell scripts (bash)

## Directory Structure
```
deploy/
├── terraform/          # Infrastructure provisioning
│   ├── modules/        # Reusable Terraform modules
│   │   ├── talos-cluster/      # Abstract Talos K8s cluster
│   │   ├── provider-aws/       # AWS-specific resources
│   │   ├── provider-gcp/       # GCP-specific resources
│   │   ├── provider-digitalocean/
│   │   ├── ledger-backup/       # Ledger backup
│   │   ├── dns/                # Multi-provider DNS
│   │   ├── tailscale-subnet-router/
│   │   └── cost-alerts/
│   ├── environments/   # Environment configs (dev, staging, production)
│   └── regions/        # Regional mappings (nyc1, sfo1)
├── flux/               # GitOps configurations
│   ├── clusters/       # Cluster-specific Flux configs
│   ├── infrastructure/ # Controllers, policies, RBAC
│   │   ├── base/       # Shared infrastructure
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   ├── apps/           # Application deployments
│   └── notifications/
├── talos/              # Talos Linux configurations
├── policies/           # Security policies
│   ├── kyverno/        # Kyverno policies
│   └── network-policies/
├── scripts/            # Automation scripts
├── runbooks/           # Operational runbooks
├── alerts/             # Prometheus alerting rules
├── slos/               # Service Level Objectives
├── docs/               # Documentation
├── load-tests/         # Load testing configs
└── dr-drill-results/   # Disaster recovery drill results
```

## Environments
| Environment | Regions              | Purpose                       |
|-------------|----------------------|-------------------------------|
| Development | Local (Docker)       | Local dev with `inferadb dev` |
| Staging     | NYC1 + monthly drills| Pre-production validation     |
| Production  | NYC1, SFO1           | Production workloads          |

## InferaDB Components
- **Ledger**: Distributed database backend with cryptographic verification
- **Engine**: Authorization policy decision engine
- **Control**: Control plane API
- **Dashboard**: Web console
