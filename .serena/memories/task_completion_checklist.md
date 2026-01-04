# Task Completion Checklist

## Before Committing Changes

### Terraform Changes
1. **Format code**
   ```bash
   terraform fmt -recursive terraform/
   ```

2. **Validate configuration**
   ```bash
   cd terraform/environments/<env>
   terraform validate
   ```

3. **Run plan to verify changes**
   ```bash
   terraform plan
   ```

4. **Check for sensitive data**
   - Ensure no secrets in plain text
   - Mark sensitive outputs appropriately
   - Use SOPS for encrypted files

### Flux/Kubernetes YAML Changes
1. **Validate YAML syntax**
   ```bash
   kubectl apply --dry-run=client -f <file>
   ```

2. **Validate Kustomize builds**
   ```bash
   flux build kustomization <name> --path <path>
   ```

3. **Check for hardcoded values**
   - Use ConfigMaps/Secrets for configuration
   - Use Kustomize patches for environment differences

### Shell Script Changes
1. **Check script syntax**
   ```bash
   bash -n <script.sh>
   ```

2. **Ensure proper error handling**
   - `set -euo pipefail` at start
   - Proper argument validation

### All Changes
1. **Run linting** (if applicable tools are installed)
   ```bash
   # Terraform
   tflint terraform/
   
   # YAML
   yamllint .
   ```

2. **Update documentation if needed**
   - README.md updates
   - Runbook updates
   - ADR creation for architectural decisions

3. **Security review**
   - No exposed credentials
   - Network policies in place
   - RBAC properly scoped

## After Applying Changes

### Infrastructure Changes
1. Verify cluster health:
   ```bash
   talosctl health
   kubectl get nodes
   ```

2. Verify Flux reconciliation:
   ```bash
   flux get kustomizations
   flux get helmreleases -A
   ```

3. Check for any failed pods:
   ```bash
   kubectl get pods -A | grep -v Running
   ```

### Application Changes
1. Verify application health:
   ```bash
   kubectl get pods -n inferadb
   ```

2. Check logs for errors:
   ```bash
   kubectl logs -n inferadb -l app.kubernetes.io/part-of=inferadb --tail=100
   ```

## Git Commit Guidelines
- Use conventional commit format
- Reference related issues
- Keep commits atomic and focused

```
feat(terraform): add cost alerts module

- Add CloudWatch/Stackdriver cost alerting
- Configure thresholds per environment
- Add documentation

Closes #123
```
