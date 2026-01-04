# InferaDB Terraform Infrastructure

This directory contains Terraform modules and configurations for deploying InferaDB clusters across multiple cloud providers and regions.

## Directory Structure

```
terraform/
├── modules/           # Reusable Terraform modules
│   └── talos-cluster/ # Abstract Talos Kubernetes cluster module
├── environments/      # Environment-specific configurations
│   ├── dev/          # Development environment
│   ├── staging/      # Staging environment
│   └── production/   # Production environment
└── regions/          # Regional configuration mappings
    ├── nyc1/         # New York City region
    └── sfo1/         # San Francisco region
```

## Modules

### talos-cluster

Abstract module for provisioning Talos Linux Kubernetes clusters across multiple cloud providers (AWS, GCP, DigitalOcean).

**Files:**
- `main.tf` - Main cluster provisioning logic with provider-specific resources
- `variables.tf` - Module input variables
- `outputs.tf` - Module outputs (kubeconfig, talosconfig, endpoints)
- `versions.tf` - Provider version requirements
- `spot.tf` - Spot/preemptible instance configurations for cost optimization
- `asg-mixed.tf` - AWS Auto Scaling Group with mixed instances policy

**Key Features:**
- Provider-agnostic interface
- Support for spot/preemptible instances (60-70% cost savings)
- Machine type abstraction (small, medium, large)
- Automatic control plane load balancing
- Talos machine configuration generation

**Usage:**

```hcl
module "cluster" {
  source = "../../modules/talos-cluster"

  cluster_name        = "inferadb-prod-nyc1"
  provider_type       = "aws"
  region              = "nyc1"
  provider_region     = "us-east-1"
  environment         = "production"

  control_plane_count = 3
  worker_count        = 5
  worker_machine_type = "large"

  use_spot_instances  = false
  talos_version       = "v1.8.0"
  kubernetes_version  = "1.30.0"

  vpc_id             = "vpc-xxxxx"
  subnet_ids         = ["subnet-a", "subnet-b", "subnet-c"]
}
```

## Regions

Region modules provide provider-specific mappings for InferaDB regions.

### nyc1 (New York City 1)
- AWS: `us-east-1`
- GCP: `us-east4`
- DigitalOcean: `nyc1`
- Primary region: Yes

### sfo1 (San Francisco 1)
- AWS: `us-west-1`
- GCP: `us-west1`
- DigitalOcean: `sfo3`
- Primary region: No (DR/Secondary)

## Environments

### Development
- Minimal resources (1 control plane, 2 workers)
- Spot instances enabled by default
- Small machine types
- Local state backend

### Staging
- Production-like configuration (3 control planes, 3 workers)
- Spot instances for stateless workloads
- Medium machine types
- Optional multi-region deployment
- Remote state backend (S3)

### Production
- High availability (3 control planes, 5 workers per region)
- No spot instances for stateful workloads
- Large machine types
- Multi-region deployment (NYC1 + SFO1)
- Remote state backend with locking

## Machine Type Mappings

AWS uses Graviton (ARM64) instances for ~20% cost savings over x86.

| Size   | AWS (Graviton) | GCP             | DigitalOcean  |
|--------|----------------|-----------------|---------------|
| small  | t4g.medium     | e2-medium       | s-2vcpu-4gb   |
| medium | t4g.xlarge     | e2-standard-4   | s-4vcpu-8gb   |
| large  | t4g.2xlarge    | e2-standard-8   | s-8vcpu-16gb  |

## Spot Instance Strategy

Spot instances provide 60-70% cost savings for stateless workloads:

- **AWS**: Mixed instances policy with capacity-optimized allocation
- **GCP**: Spot VMs with STOP termination action
- **Strategy**: 1 on-demand base instance + spot for additional capacity

**Important**: Never use spot instances for:
- FoundationDB storage nodes
- Control plane nodes
- Stateful workloads requiring guaranteed uptime

## Getting Started

1. **Choose an environment:**
   ```bash
   cd environments/dev  # or staging, production
   ```

2. **Configure variables:**
   - Edit `terraform.tfvars` or create it based on requirements
   - Set `provider_type`, `vpc_id`, `subnet_ids`, etc.

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan deployment:**
   ```bash
   terraform plan
   ```

5. **Apply configuration:**
   ```bash
   terraform apply
   ```

6. **Access cluster:**
   ```bash
   # Export kubeconfig
   terraform output -raw kubeconfig > ~/.kube/inferadb-dev
   export KUBECONFIG=~/.kube/inferadb-dev

   # Verify cluster
   kubectl get nodes
   ```

## State Management

- **Dev**: Local state backend
- **Staging/Production**: Remote state in S3 with DynamoDB locking

**State Backend Configuration:**
```hcl
backend "s3" {
  bucket         = "inferadb-terraform-state-production"
  key            = "production/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "inferadb-terraform-locks"
}
```

## Adding a New Region

1. Create region directory:
   ```bash
   cp -r regions/_template regions/new-region
   ```

2. Update `variables.tf`:
   - Set region mappings for each provider
   - Configure machine type mappings (if needed)

3. Create outputs.tf:
   - Export region_mappings and machine_type_mappings

4. Reference in environment configurations

## Security Considerations

- All EBS volumes are encrypted
- All state files are encrypted at rest
- Kubeconfig and talosconfig are marked as sensitive
- Production uses separate state buckets with versioning
- Control plane load balancers are internal-only

## Cost Optimization

- Use spot instances for dev/staging
- Use small/medium machine types for non-production
- Enable autoscaling for worker nodes
- Monitor spot interruption rates
- Use CloudWatch alarms for high interruption rates

## Next Steps

After provisioning infrastructure:
1. Bootstrap Flux GitOps (see `flux/` directory)
2. Deploy Cilium CNI
3. Configure External Secrets Operator
4. Deploy FoundationDB Operator
5. Deploy InferaDB applications

## References

- [Talos Linux Documentation](https://www.talos.dev/)
- [Terraform Registry - Talos Provider](https://registry.terraform.io/providers/siderolabs/talos/latest)
- [DEPLOYMENT_PLAN.md](../DEPLOYMENT_PLAN.md) - Detailed architecture
