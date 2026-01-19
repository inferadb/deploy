# Code Style and Conventions

## Terraform (HCL)

### Variable Definitions
- Always include `type`, `description`
- Use `validation` blocks for constrained values
- Provide sensible `default` values where appropriate
- Use snake_case for variable names

```hcl
variable "worker_machine_type" {
  type        = string
  default     = "medium"
  description = "Machine type for workers: small, medium, large"
  validation {
    condition     = contains(["small", "medium", "large"], var.worker_machine_type)
    error_message = "Worker machine type must be one of: small, medium, large"
  }
}
```

### File Organization
- `main.tf` - Primary resources
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `versions.tf` - Provider requirements
- Feature-specific files (e.g., `spot.tf`, `asg-mixed.tf`)

### Naming Conventions
- Modules: `kebab-case` (e.g., `talos-cluster`, `ledger-backup`)
- Resources: `snake_case`
- Environments: lowercase (`dev`, `staging`, `production`)
- Regions: InferaDB-specific identifiers (e.g., `nyc1`, `sfo1`)

### Module Structure
```
terraform/modules/<module-name>/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── <feature>.tf  # Optional feature-specific files
```

## YAML (Kubernetes/Flux)

### Kustomize Structure
```
flux/infrastructure/
├── base/           # Shared resources
│   ├── controllers/
│   ├── namespaces/
│   ├── policies/
│   ├── rbac/
│   ├── sources/
│   └── kustomization.yaml
├── dev/
├── staging/
└── production/
```

### Resource Naming
- Use kebab-case for resource names
- Include environment in cluster-specific names
- Use consistent labels

### Standard Labels
```yaml
labels:
  app.kubernetes.io/name: <component>
  app.kubernetes.io/instance: <instance>
  app.kubernetes.io/part-of: inferadb
  environment: <dev|staging|production>
```

## Shell Scripts

### Headers
```bash
#!/bin/bash
set -euo pipefail
```

### Naming
- Use kebab-case for script names
- Descriptive names (e.g., `bootstrap-cluster.sh`, `staging-dr-drill.sh`)

### Arguments
```bash
# Positional arguments with validation
if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <environment> <region> <provider>"
  exit 1
fi
```

## Security Conventions

### Secrets
- Never commit unencrypted secrets
- Use SOPS + Age for secret encryption
- Use External Secrets Operator for Kubernetes secrets
- Mark sensitive outputs in Terraform

### Pod Security
- Enforce Pod Security Standards at namespace level
- Use Cilium NetworkPolicies with default deny
- Require image signing verification via Kyverno

### State Management
- Dev: Local state
- Staging/Production: Remote state with encryption and locking

## Design Patterns

### Provider Abstraction
The `talos-cluster` module abstracts cloud providers:
- Common interface for AWS, GCP, DigitalOcean
- Machine type mapping (small/medium/large)
- Provider-specific implementations hidden

### Environment Layering
- Base configurations shared across environments
- Environment-specific overlays via Kustomize
- Region-specific variables in separate directories

### GitOps Flow
1. Terraform provisions infrastructure
2. Flux bootstrapped to cluster
3. Flux deploys infrastructure components
4. Flux deploys applications
