# Suggested Commands

## Tool Installation
```bash
# Install all required tools via mise
mise install

# Verify all tools are installed
mise run check-tools
```

## Local Development
```bash
# Start local dev cluster (uses InferaDB CLI)
inferadb dev start
# Or via mise:
mise run dev-up

# Show cluster status
inferadb dev status

# Stop and destroy local cluster
inferadb dev stop --destroy
# Or via mise:
mise run dev-down
```

## Port Forwarding (Local Dev)
```bash
kubectl port-forward -n inferadb svc/inferadb-engine 8080:8080
kubectl port-forward -n inferadb svc/inferadb-control 9090:9090
kubectl port-forward -n inferadb svc/inferadb-dashboard 3000:3000
```

## Terraform Commands
```bash
# Navigate to environment
cd terraform/environments/<env>  # dev, staging, production

# Initialize
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Get outputs
terraform output -raw kubeconfig > ~/.kube/inferadb-<env>
```

## Cluster Bootstrap (Staging/Production)
```bash
# Bootstrap a new cluster
./scripts/bootstrap-cluster.sh <environment> <region> <provider>

# Example: Bootstrap staging NYC1 on AWS
./scripts/bootstrap-cluster.sh staging nyc1 aws

# Bootstrap secrets
./scripts/bootstrap-secrets.sh <environment>
```

## Flux GitOps
```bash
# Check Flux status
flux check

# Reconcile all resources
flux reconcile kustomization flux-system

# Get Kustomizations status
flux get kustomizations

# Get HelmReleases status
flux get helmreleases -A
```

## Talos Commands
```bash
# Get cluster health
talosctl health

# Get node information
talosctl get nodes

# Apply machine config
talosctl apply-config --nodes <node> --file <config.yaml>

# Generate Talos configs with talhelper
talhelper genconfig
```

## Kubernetes Commands
```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/inferadb-dev

# Get nodes
kubectl get nodes

# Get pods in inferadb namespace
kubectl get pods -n inferadb

# Get all Flux resources
kubectl get kustomizations,helmreleases,gitrepositories -A
```

## Secret Management
```bash
# Encrypt secret with SOPS
sops -e secrets.yaml > secrets.enc.yaml

# Decrypt secret
sops -d secrets.enc.yaml

# Edit encrypted secret in place
sops secrets.enc.yaml
```

## Disaster Recovery Drills
```bash
# Run staging DR drill
./scripts/staging-dr-drill.sh
```

## Git Commands
```bash
# Standard git operations
git status
git diff
git add .
git commit -m "message"
git push

# Using GitHub CLI
gh pr create
gh pr list
gh pr view
```

## System Utilities (macOS/Darwin)
```bash
# List files
ls -la

# Find files
find . -name "*.tf"

# Search in files
grep -r "pattern" .

# JSON processing
jq '.key' file.json
```
