# InferaDB Multi-Environment Deployment Architecture

## Executive Summary

This document outlines a modular, vendor-agnostic deployment architecture for InferaDB
supporting three environments (Development, Staging, Production) across multiple cloud
providers and regions. The architecture leverages existing patterns from the codebase
while introducing a GitOps-based approach using Flux, Terraform, and Kubernetes on
Talos Linux.

---

## 1. Technology Stack Validation

### Recommended Stack (Validated)

| Component                 | Technology                       | Rationale                                                                                                             |
| ------------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **OS**                    | Talos Linux                      | Immutable, API-driven, purpose-built for Kubernetes. Eliminates SSH attack surface and drift.                         |
| **Orchestration**         | Kubernetes                       | Already extensively used in existing infrastructure (engine/k8s/, helm charts, terraform modules).                    |
| **GitOps**                | Flux CD                          | Native Kubernetes, supports multi-tenancy, Kustomize overlays, and Helm. Better suited for multi-cluster than ArgoCD. |
| **IaC**                   | Terraform + OpenTofu             | Existing terraform modules in `terraform/`. OpenTofu as vendor-neutral alternative.                                   |
| **CNI**                   | Cilium                           | eBPF-based networking with built-in NetworkPolicies, mTLS, and observability. Required for defense-in-depth.          |
| **Networking**            | Tailscale                        | Already integrated in Helm values. Provides encrypted mesh without complex VPN configuration.                         |
| **Secret Management**     | External Secrets Operator + SOPS | ESO for runtime secrets from Vault/AWS SM. SOPS for bootstrap secrets in git.                                         |
| **Supply Chain Security** | Cosign + Sigstore + Trivy        | Image signing, verification, SBOM generation, and vulnerability scanning.                                             |

### Alternative Considerations

| Alternative                     | Assessment                                                                                                       |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **k3s instead of Talos**        | Lighter weight but lacks immutability guarantees. Better for edge/IoT. Not recommended for enterprise SaaS.      |
| **ArgoCD instead of Flux**      | Superior UI but weaker multi-cluster support. Flux's native multi-tenancy aligns better with regional isolation. |
| **Pulumi instead of Terraform** | Better type safety but smaller ecosystem. Existing Terraform modules favor staying with Terraform.               |
| **Calico instead of Cilium**    | More mature but lacks eBPF performance benefits and native mTLS.                                                 |

---

## 2. Directory Structure

```text
deploy/
├── README.md                          # Documentation entry point
├── DEPLOYMENT_PLAN.md                 # This document
│
├── terraform/                         # Infrastructure provisioning
│   ├── modules/                       # Reusable Terraform modules
│   │   ├── talos-cluster/             # Talos K8s cluster provisioning
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── versions.tf
│   │   ├── provider-aws/              # AWS-specific resources (VPC, EKS node pools, etc.)
│   │   ├── provider-gcp/              # GCP-specific resources
│   │   ├── provider-digitalocean/     # DigitalOcean-specific resources
│   │   ├── tailscale-subnet-router/   # Tailscale subnet router deployment
│   │   ├── fdb-backup/                # FDB backup infrastructure (S3/GCS buckets)
│   │   └── dns/                       # Multi-provider DNS management
│   │
│   ├── environments/                  # Environment-specific configurations
│   │   ├── dev/                       # Local development (uses Talos on Docker/QEMU)
│   │   │   ├── main.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   ├── staging/                   # Staging environment
│   │   │   ├── main.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   └── production/                # Production environment
│   │       ├── main.tf
│   │       ├── terraform.tfvars
│   │       └── backend.tf
│   │
│   └── regions/                       # Regional cluster definitions
│       ├── nyc1/                      # NYC1 region configuration
│       │   ├── aws/                   # NYC1 on AWS (us-east-1)
│       │   ├── digitalocean/          # NYC1 on DigitalOcean (nyc1)
│       │   └── variables.tf
│       ├── sfo1/                      # SFO1 region configuration
│       │   ├── aws/                   # SFO1 on AWS (us-west-1)
│       │   ├── gcp/                   # SFO1 on GCP (us-west1)
│       │   └── variables.tf
│       └── _template/                 # Template for adding new regions
│
├── flux/                              # GitOps configurations
│   ├── clusters/                      # Cluster-specific Flux configs
│   │   ├── dev-local/                 # Development cluster
│   │   │   ├── flux-system/
│   │   │   └── infrastructure.yaml    # Kustomization reference
│   │   ├── staging-nyc1/
│   │   ├── staging-sfo1/
│   │   ├── prod-nyc1/
│   │   └── prod-sfo1/
│   │
│   ├── infrastructure/                # Cluster infrastructure components
│   │   ├── base/                      # Shared infrastructure
│   │   │   ├── sources/               # HelmRepository, GitRepository, OCIRepository
│   │   │   ├── controllers/           # Flux controllers, operators
│   │   │   │   ├── cilium/            # CNI with NetworkPolicies + mTLS
│   │   │   │   ├── external-secrets/
│   │   │   │   ├── fdb-operator/
│   │   │   │   ├── cert-manager/
│   │   │   │   ├── tailscale-operator/
│   │   │   │   ├── prometheus-operator/
│   │   │   │   ├── loki/              # Log aggregation
│   │   │   │   ├── tempo/             # Distributed tracing
│   │   │   │   ├── trivy-operator/    # Runtime vulnerability scanning
│   │   │   │   ├── flagger/           # Progressive delivery
│   │   │   │   └── fdb-exporter/      # FDB Prometheus metrics
│   │   │   ├── policies/              # Kyverno/OPA policies
│   │   │   ├── rbac/                  # Kubernetes RBAC definitions
│   │   │   └── kustomization.yaml
│   │   │
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   │
│   ├── apps/                          # Application deployments
│   │   ├── base/
│   │   │   ├── foundationdb/          # FDB FoundationDBCluster CRD + backup jobs
│   │   │   ├── engine/                # Engine + canary config
│   │   │   ├── control/
│   │   │   ├── dashboard/
│   │   │   ├── namespaces/            # PSA-configured namespaces
│   │   │   └── kustomization.yaml
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   │
│   └── notifications/                 # Alert routing
│       ├── slack.yaml
│       ├── pagerduty.yaml
│       └── kustomization.yaml
│
├── talos/                             # Talos Linux configurations
│   ├── controlplane.yaml              # Control plane machine config template
│   ├── worker.yaml                    # Worker node machine config template
│   ├── talconfig.yaml                 # Talhelper configuration
│   └── patches/                       # Machine config patches (applied via talhelper)
│       ├── common/                    # Applied to all nodes
│       │   ├── cilium.yaml            # CNI configuration
│       │   ├── kubelet.yaml           # Kubelet settings
│       │   └── sysctls.yaml           # Kernel parameters
│       ├── dev/
│       ├── staging/
│       └── production/
│           ├── hardening.yaml         # Security hardening
│           └── audit.yaml             # Audit logging
│
├── policies/                          # Policy-as-code
│   ├── kyverno/                       # Kyverno cluster policies
│   │   ├── require-signed-images.yaml
│   │   ├── restrict-registries.yaml
│   │   ├── require-labels.yaml
│   │   └── restrict-capabilities.yaml
│   └── network-policies/              # Cilium NetworkPolicies
│       ├── base/
│       ├── staging/
│       └── production/
│
├── scripts/                           # Deployment automation scripts
│   ├── dev-up.sh
│   ├── dev-down.sh
│   ├── bootstrap-cluster.sh
│   ├── bootstrap-secrets.sh           # Initial secret bootstrapping
│   ├── rotate-secrets.sh
│   ├── disaster-recovery.sh
│   ├── talos-upgrade.sh               # Talos Linux upgrade orchestration
│   ├── fdb-backup.sh                  # FDB backup procedures
│   ├── fdb-restore.sh                 # FDB restore procedures
│   └── chaos/                         # Chaos engineering scripts
│       ├── network-partition.sh
│       ├── fdb-process-kill.sh
│       └── tailscale-disconnect.sh
│
├── runbooks/                          # Operational runbooks
│   ├── fdb-cluster-recovery.md
│   ├── node-replacement.md
│   ├── certificate-rotation.md
│   ├── partial-region-degradation.md
│   ├── full-region-failover.md
│   ├── secret-rotation.md
│   ├── fdb-upgrade.md
│   └── break-glass-procedures.md
│
├── alerts/                            # Alerting definitions
│   ├── prometheusrules/
│   │   ├── fdb-alerts.yaml
│   │   ├── engine-alerts.yaml
│   │   ├── control-alerts.yaml
│   │   └── infrastructure-alerts.yaml
│   └── alertmanager/
│       └── config.yaml
│
├── slos/                              # Service Level Objectives
│   ├── engine-slos.yaml
│   ├── control-slos.yaml
│   └── slo-definitions.md
│
├── load-tests/                        # Load testing
│   ├── k6/                            # k6 load test scripts
│   │   ├── engine-check.js
│   │   ├── control-api.js
│   │   └── full-flow.js
│   └── results/                       # Test result baselines
│
└── docs/
    ├── getting-started.md
    ├── adding-regions.md
    ├── adding-providers.md
    ├── disaster-recovery.md
    ├── troubleshooting.md
    ├── security-model.md
    ├── cost-estimation.md
    └── architecture-decisions/        # ADRs
        ├── 001-talos-linux.md
        ├── 002-flux-over-argocd.md
        ├── 003-cilium-cni.md
        └── 004-fdb-regional-clusters.md
```

---

## 3. Security Architecture

### 3.1 Network Security (Defense in Depth)

#### Layer 1: Cilium CNI with NetworkPolicies

**Default Deny Policy:**

```yaml
# policies/network-policies/production/default-deny.yaml
# Default deny all ingress and egress - explicit allowlist required
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-all
  namespace: inferadb
spec:
  endpointSelector: {} # Applies to all pods in namespace
  ingress:
    - {} # Placeholder - will be denied without explicit rules
  egress:
    - {} # Placeholder - will be denied without explicit rules
```

**FoundationDB Network Policy (Strict Egress):**

```yaml
# policies/network-policies/production/fdb-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: foundationdb-policy
  namespace: inferadb
spec:
  endpointSelector:
    matchLabels:
      app: foundationdb
  ingress:
    # Allow traffic from engine
    - fromEndpoints:
        - matchLabels:
            app: inferadb-engine
      toPorts:
        - ports:
            - port: "4500"
              protocol: TCP
    # Allow traffic from other FDB processes (cluster coordination)
    - fromEndpoints:
        - matchLabels:
            app: foundationdb
      toPorts:
        - ports:
            - port: "4500"
              protocol: TCP
            - port: "4501" # Coordination port
              protocol: TCP
    # Allow Prometheus scraping
    - fromEndpoints:
        - matchLabels:
            app: fdb-prometheus-exporter
      toPorts:
        - ports:
            - port: "4500"
              protocol: TCP
  egress:
    # FDB cluster coordination only - NO internet access
    - toEndpoints:
        - matchLabels:
            app: foundationdb
      toPorts:
        - ports:
            - port: "4500"
              protocol: TCP
            - port: "4501"
              protocol: TCP
    # DNS resolution (required for service discovery)
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    # S3/GCS for backups (backup agent runs on FDB pods)
    - toFQDNs:
        - matchPattern: "*.s3.amazonaws.com"
        - matchPattern: "*.s3.*.amazonaws.com"
        - matchPattern: "storage.googleapis.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    # EXPLICITLY DENY all other egress (internet access blocked)
```

**Engine Network Policy:**

```yaml
# policies/network-policies/production/inferadb-namespace.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: inferadb-engine-policy
  namespace: inferadb
spec:
  endpointSelector:
    matchLabels:
      app: inferadb-engine
  ingress:
    # Allow traffic from control plane
    - fromEndpoints:
        - matchLabels:
            app: inferadb-control
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
            - port: "8081"
              protocol: TCP
    # Allow traffic from other engine instances (mesh)
    - fromEndpoints:
        - matchLabels:
            app: inferadb-engine
      toPorts:
        - ports:
            - port: "8082"
              protocol: TCP
    # Allow Prometheus scraping
    - fromEndpoints:
        - matchLabels:
            app.kubernetes.io/name: prometheus
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
  egress:
    # Allow FDB connections
    - toEndpoints:
        - matchLabels:
            app: foundationdb
      toPorts:
        - ports:
            - port: "4500"
              protocol: TCP
    # Allow DNS
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
```

#### Layer 2: Cilium Encryption (WireGuard)

WireGuard provides transparent encryption for all pod-to-pod traffic without the
operational complexity of SPIRE. This is sufficient for most compliance requirements
and significantly simpler to operate.

```yaml
# flux/infrastructure/base/controllers/cilium/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cilium
  namespace: kube-system
spec:
  interval: 10m
  chart:
    spec:
      chart: cilium
      version: "1.15.x"
      sourceRef:
        kind: HelmRepository
        name: cilium
        namespace: flux-system
  values:
    # Observability
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
      metrics:
        enabled:
          - dns
          - drop
          - tcp
          - flow
          - port-distribution
          - icmp
          - httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction

    # WireGuard encryption - simpler than SPIRE mTLS
    encryption:
      enabled: true
      type: wireguard
      # Encrypt node-to-node traffic (required for cross-region)
      nodeEncryption: true

    # L7 policy enforcement (alternative to mTLS for service identity)
    # Uses Cilium's native identity system instead of SPIRE
    l7Proxy: true

    # IPAM
    ipam:
      mode: kubernetes
```

**Why WireGuard over SPIRE mTLS:**

| Aspect                     | WireGuard                            | SPIRE mTLS                             |
| -------------------------- | ------------------------------------ | -------------------------------------- |
| **Operational Complexity** | Low - built into Cilium              | High - separate SPIRE server, agents   |
| **Certificate Management** | None - WireGuard uses Noise protocol | Requires X.509 PKI, rotation           |
| **Performance**            | Kernel-level, ~3% overhead           | Userspace proxy, ~10-15% overhead      |
| **Workload Identity**      | Cilium's native identity             | Full SPIFFE identity attestation       |
| **Compliance**             | SOC2, HIPAA encryption requirements  | SOC2, HIPAA, some FedRAMP requirements |

**When to Consider SPIRE (Future Enhancement):**

SPIRE adds workload identity attestation if you need:

- Cross-cluster mTLS with identity verification
- SPIFFE identity for external service authentication
- Specific compliance requirements (FedRAMP High)

```yaml
# flux/infrastructure/production/controllers/cilium/spire-overlay.yaml
# Only enable if compliance requires workload identity attestation
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: cilium
  namespace: kube-system
spec:
  values:
    authentication:
      mutual:
        spire:
          enabled: true
          install:
            enabled: true
            server:
              dataStorage:
                storageClass: fast-ssd
```

#### Layer 3: Tailscale ACLs (Cross-Region)

Already defined in Section 8 - provides encrypted WireGuard tunnels between regions.

### 3.2 Supply Chain Security

#### Image Signing with Cosign

```yaml
# .github/workflows/build-push.yaml (referenced, not created)
# Images are signed during CI/CD pipeline:
# cosign sign --key cosign.key ghcr.io/inferadb/engine:${VERSION}

# flux/infrastructure/base/policies/require-signed-images.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: verify-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "ghcr.io/inferadb/*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/inferadb/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
```

#### Registry Restrictions

```yaml
# flux/infrastructure/base/policies/restrict-registries.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-registries
spec:
  validationFailureAction: Enforce
  rules:
    - name: allowed-registries
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Images must come from approved registries"
        pattern:
          spec:
            containers:
              - image: "ghcr.io/inferadb/* | docker.io/library/* | quay.io/prometheus/* | registry.k8s.io/*"
```

#### Vulnerability Scanning

```yaml
# flux/infrastructure/base/controllers/trivy-operator/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: trivy-operator
  namespace: trivy-system
spec:
  interval: 10m
  chart:
    spec:
      chart: trivy-operator
      version: "0.20.x"
      sourceRef:
        kind: HelmRepository
        name: aqua
        namespace: flux-system
  values:
    trivy:
      severity: "CRITICAL,HIGH"
    operator:
      scanJobsConcurrentLimit: 3
      vulnerabilityScannerEnabled: true
      configAuditScannerEnabled: true
      sbomGenerationEnabled: true # Generate SBOMs
```

### 3.3 Pod Security Standards (PSA)

Enforce Pod Security Standards at the namespace level. Kyverno provides additional flexibility, but PSA is the baseline:

```yaml
# flux/infrastructure/base/namespaces/inferadb.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: inferadb
  labels:
    # Enforce restricted profile - most secure
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    # Warn on baseline violations (allows debugging)
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    # Audit for compliance tracking
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
---
# flux/infrastructure/base/namespaces/monitoring.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    # Monitoring needs baseline for node access (Promtail, node-exporter)
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
---
# flux/infrastructure/base/namespaces/kube-system-override.yaml
# kube-system keeps privileged for CNI, CSI drivers
apiVersion: v1
kind: Namespace
metadata:
  name: kube-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: baseline
```

**PSA Levels:**

| Level        | Description                                      | Use Case                     |
| ------------ | ------------------------------------------------ | ---------------------------- |
| `privileged` | No restrictions                                  | System components (CNI, CSI) |
| `baseline`   | Minimal restrictions, prevents known escalations | Monitoring, logging          |
| `restricted` | Heavily restricted, security best practices      | Application workloads        |

**Workload Adjustments for Restricted Profile:**

```yaml
# flux/apps/base/engine/deployment-patch.yaml
# Engine must comply with restricted PSA
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534 # nobody
        runAsGroup: 65534
        fsGroup: 65534
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: engine
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: cache
              mountPath: /var/cache
      volumes:
        - name: tmp
          emptyDir: {}
        - name: cache
          emptyDir: {}
```

### 3.4 Kubernetes RBAC

```yaml
# flux/infrastructure/base/rbac/flux-reconciler.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flux-reconciler
rules:
  - apiGroups: ["helm.toolkit.fluxcd.io"]
    resources: ["helmreleases"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["kustomize.toolkit.fluxcd.io"]
    resources: ["kustomizations"]
    verbs: ["get", "list", "watch"]
  # Deny create/update/delete - only Flux service accounts can modify
---
# flux/infrastructure/base/rbac/inferadb-admin.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: inferadb-admin
rules:
  - apiGroups: ["apps.foundationdb.org"]
    resources: ["foundationdbclusters"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
    resourceNames: ["fdb-cli"] # Only allow exec into FDB CLI pod
---
# flux/infrastructure/production/rbac/bindings.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: production-admins
subjects:
  - kind: Group
    name: "inferadb:production-admins"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: inferadb-admin
  apiGroup: rbac.authorization.k8s.io
```

### 3.4 Secrets Management Lifecycle

#### Bootstrap Secrets (Chicken-Egg Problem)

```bash
#!/bin/bash
# scripts/bootstrap-secrets.sh
set -euo pipefail

ENVIRONMENT=${1:-staging}
CLUSTER=${2:-nyc1}

echo "Bootstrapping secrets for ${ENVIRONMENT}-${CLUSTER}"

# Step 1: Generate SOPS age key (stored securely, never in git)
if [ ! -f ~/.config/sops/age/keys.txt ]; then
  age-keygen -o ~/.config/sops/age/keys.txt
fi

# Step 2: Create bootstrap secret for External Secrets Operator
# This secret allows ESO to authenticate with the secret provider
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-secretsmanager-credentials
  namespace: external-secrets
type: Opaque
stringData:
  access-key: $(aws configure get aws_access_key_id)
  secret-access-key: $(aws configure get aws_secret_access_key)
EOF

# Step 3: Create SOPS-encrypted secrets for Flux (git-stored)
# These are decrypted by Flux's kustomize-controller
sops --encrypt --age $(cat ~/.config/sops/age/keys.txt | grep "public key" | cut -d: -f2 | tr -d ' ') \
  flux/clusters/${ENVIRONMENT}-${CLUSTER}/secrets.yaml.dec > \
  flux/clusters/${ENVIRONMENT}-${CLUSTER}/secrets.yaml

echo "Bootstrap complete. ESO can now sync remaining secrets."
```

#### Runtime Secrets via External Secrets Operator

```yaml
# flux/apps/base/engine/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: engine-secrets
  namespace: inferadb
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: engine-secrets
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        jwt-private-key: "{{ .jwt_private_key }}"
        fdb-cluster-file: "{{ .fdb_cluster_file }}"
  data:
    - secretKey: jwt_private_key
      remoteRef:
        key: inferadb/engine/jwt-private-key
    - secretKey: fdb_cluster_file
      remoteRef:
        key: inferadb/fdb/cluster-file
```

#### Break-Glass Procedures

```markdown
# runbooks/break-glass-procedures.md

## When Vault/Secret Provider is Unavailable

### Symptoms

- External Secrets Operator showing sync failures
- New pods failing to start (missing secrets)

### Immediate Actions

1. **Verify the issue is with the secret provider**
   kubectl get externalsecrets -A -o wide
   kubectl logs -n external-secrets deploy/external-secrets

2. **Use cached secrets (pods keep running)**

   - Existing pods retain their secrets in memory
   - Avoid restarting pods unless necessary

3. **Emergency secret injection (requires break-glass access)**

   # Requires inferadb:break-glass group membership

   # Audited and alerts triggered

   kubectl create secret generic engine-secrets-emergency \
    --from-file=jwt-private-key=/secure/backup/jwt-key.pem \
    --dry-run=client -o yaml | kubectl apply -f -

4. **Patch deployments to use emergency secret**
   kubectl patch deployment inferadb-engine -p '
   {"spec":{"template":{"spec":{"containers":[{
   "name":"engine",
   "envFrom":[{"secretRef":{"name":"engine-secrets-emergency"}}]
   }]}}}}'

### Post-Incident

- Rotate all secrets that were manually injected
- Review audit logs for break-glass access
- Document incident in post-mortem
```

---

## 4. Environment Parity Strategy

### Principle: "Dev mirrors Prod, just smaller"

| Aspect                 | Development                    | Staging                          | Production                                   |
| ---------------------- | ------------------------------ | -------------------------------- | -------------------------------------------- |
| **Cluster Type**       | Talos on Docker (single node)  | Talos on cloud (3 CP, 2 workers) | Talos on cloud (3 CP, 3+ workers per region) |
| **Regions**            | 1 (local)                      | 1 (NYC1) + monthly DR drills     | 2+ (NYC1, SFO1, expandable)                  |
| **FoundationDB**       | Single-node, single redundancy | 3-node, double redundancy        | 5+ node, three_data_hall                     |
| **Engine Replicas**    | 1                              | 2                                | 3+ (autoscaling 3-15)                        |
| **Control Replicas**   | 1                              | 2                                | 2+ (autoscaling 2-6)                         |
| **Dashboard Replicas** | 1                              | 1                                | 2+                                           |
| **Tailscale**          | Optional                       | Required (for DR drills)         | Required (cross-region + cross-provider)     |
| **TLS**                | Self-signed (cert-manager)     | Let's Encrypt staging            | Let's Encrypt production                     |
| **Secrets**            | SOPS (local)                   | External Secrets (staging vault) | External Secrets (production vault)          |
| **Network Policies**   | Permissive (dev iteration)     | Enforced (same as prod)          | Enforced (strict)                            |
| **Image Signing**      | Optional                       | Required                         | Required                                     |
| **FDB Backups**        | None                           | Daily                            | Continuous + hourly snapshots                |
| **Monitoring**         | Prometheus (local)             | Full stack (no alerting)         | Full stack + alerting + on-call              |
| **Spot Instances**     | N/A                            | Workers (stateless)              | Stateless workers only                       |

### Staging DR Drill Strategy

Staging runs single-region to reduce costs (~56% savings). Monthly DR drills validate multi-region capabilities:

```bash
#!/bin/bash
# scripts/staging-dr-drill.sh
# Run monthly to validate DR procedures without maintaining always-on second region

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform/environments/staging"
DRILL_WORKSPACE="sfo1-drill"
DRILL_STARTED=false

# Cleanup function - ensures temporary infra is destroyed on any exit
cleanup() {
  local exit_code=$?
  if [[ "$DRILL_STARTED" == "true" ]]; then
    echo ""
    echo "=== Cleaning up temporary DR infrastructure ==="
    cd "$TERRAFORM_DIR"
    if terraform workspace list | grep -q "$DRILL_WORKSPACE"; then
      terraform workspace select "$DRILL_WORKSPACE" 2>/dev/null || true
      terraform destroy -var="region=sfo1" -auto-approve || echo "Warning: destroy failed, manual cleanup may be required"
      terraform workspace select default
      terraform workspace delete "$DRILL_WORKSPACE" 2>/dev/null || true
    fi
  fi
  if [[ $exit_code -ne 0 ]]; then
    echo "=== DR Drill FAILED (exit code: $exit_code) ==="
  fi
  exit $exit_code
}
trap cleanup EXIT ERR INT TERM

echo "=== Staging DR Drill Started ==="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# 1. Spin up temporary SFO1 staging cluster
cd "$TERRAFORM_DIR"
terraform workspace select "$DRILL_WORKSPACE" || terraform workspace new "$DRILL_WORKSPACE"
DRILL_STARTED=true
terraform apply -var="region=sfo1" -auto-approve

# 2. Bootstrap temporary cluster
"${SCRIPT_DIR}/bootstrap-cluster.sh" staging sfo1 aws

# 3. Configure FDB async replication to temporary cluster
kubectl --context staging-sfo1 apply -f "${SCRIPT_DIR}/../flux/apps/staging/foundationdb/dr-replica.yaml"

# 4. Run DR validation tests
echo "Testing failover..."
"${SCRIPT_DIR}/dr-validation-tests.sh"

# 5. Record results before cleanup (cleanup happens in trap)
mkdir -p "${SCRIPT_DIR}/../dr-drill-results"
echo "Drill completed successfully at $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "${SCRIPT_DIR}/../dr-drill-results/$(date +%Y-%m-%d)-drill.log"

echo "=== DR Drill Complete - Results in ./dr-drill-results/ ==="
```

### Configuration Inheritance

```text
base/ (shared defaults)
  └── dev/ (minimal resources, single replica, relaxed policies)
  └── staging/ (production config, smaller scale, no alerting)
  └── production/ (full scale, HA, strict security, alerting enabled)
```

---

## 5. Provider Abstraction Layer

### Design Principle: Terraform modules abstract provider specifics

```text
┌─────────────────────────────────────────────────────────────┐
│                    terraform/modules/                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              talos-cluster (abstract)                   ││
│  │  - Inputs: node_count, machine_type, region, etc.       ││
│  │  - Outputs: kubeconfig, talosconfig, cluster_endpoint   ││
│  └─────────────────────────────────────────────────────────┘│
│            │                    │                    │       │
│  ┌─────────▼──────┐  ┌─────────▼──────┐  ┌─────────▼──────┐ │
│  │  provider-aws  │  │  provider-gcp  │  │ provider-do    │ │
│  │  - EC2/ASG     │  │  - GCE/MIG     │  │ - Droplets     │ │
│  │  - VPC/Subnet  │  │  - VPC/Subnet  │  │ - VPC          │ │
│  │  - ELB/NLB     │  │  - LB          │  │ - LB           │ │
│  │  - Route53     │  │  - Cloud DNS   │  │ - DNS          │ │
│  └────────────────┘  └────────────────┘  └────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Module Interface Contract

```hcl
# terraform/modules/talos-cluster/variables.tf
variable "cluster_name" {
  type        = string
  description = "Name of the Kubernetes cluster"
}

variable "provider_type" {
  type        = string
  description = "Cloud provider: aws, gcp, digitalocean"
}

variable "region" {
  type        = string
  description = "InferaDB region identifier (e.g., nyc1, sfo1)"
}

variable "provider_region" {
  type        = string
  description = "Provider-specific region (e.g., us-east-1, us-west1)"
}

variable "control_plane_count" {
  type        = number
  default     = 3
}

variable "worker_count" {
  type        = number
  default     = 3
}

variable "worker_machine_type" {
  type        = string
  description = "Machine type (provider-specific, mapped internally)"
}

variable "use_spot_instances" {
  type        = bool
  default     = false
  description = "Use spot/preemptible instances for stateless workers (60-70% cost savings)"
}

variable "spot_max_price" {
  type        = string
  default     = ""
  description = "Maximum spot price (empty = on-demand price cap). AWS only."
}

variable "talos_version" {
  type        = string
  default     = "v1.8.0"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.30.0"
}
```

### Region-to-Provider Mapping

```hcl
# terraform/regions/nyc1/variables.tf
locals {
  region_mappings = {
    aws          = "us-east-1"
    gcp          = "us-east4"
    digitalocean = "nyc1"
  }

  machine_type_mappings = {
    small = {
      aws          = "t3.medium"
      gcp          = "e2-medium"
      digitalocean = "s-2vcpu-4gb"
    }
    medium = {
      aws          = "t3.xlarge"
      gcp          = "e2-standard-4"
      digitalocean = "s-4vcpu-8gb"
    }
    large = {
      aws          = "t3.2xlarge"
      gcp          = "e2-standard-8"
      digitalocean = "s-8vcpu-16gb"
    }
  }
}
```

### Spot Instance Configuration

Stateless workloads (engine, control, dashboard) can run on spot/preemptible instances for 60-70% cost savings. FDB and other stateful workloads must remain on on-demand instances.

```hcl
# terraform/modules/talos-cluster/spot.tf

# AWS Spot Instance Configuration
resource "aws_launch_template" "worker_spot" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  name_prefix   = "${var.cluster_name}-worker-spot-"
  image_id      = data.aws_ami.talos.id
  instance_type = local.machine_type_mappings[var.worker_machine_type]["aws"]

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = var.spot_max_price != "" ? var.spot_max_price : null
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"  # Stop instead of terminate for faster recovery
    }
  }

  # Talos machine config is passed via user_data
  user_data = base64encode(data.talos_machine_configuration.worker.machine_configuration)

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.cluster_name}-worker-spot"
      Environment = var.environment
      SpotInstance = "true"
    }
  }
}

# GCP Preemptible Instance Configuration
resource "google_compute_instance_template" "worker_preemptible" {
  count = var.provider_type == "gcp" && var.use_spot_instances ? 1 : 0

  name_prefix  = "${var.cluster_name}-worker-spot-"
  machine_type = local.machine_type_mappings[var.worker_machine_type]["gcp"]
  region       = var.provider_region

  scheduling {
    preemptible         = true
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
    # Use Spot VMs (newer, more capacity than legacy preemptible)
    provisioning_model  = "SPOT"
    instance_termination_action = "STOP"
  }

  disk {
    source_image = data.google_compute_image.talos.self_link
    auto_delete  = true
    boot         = true
  }

  metadata = {
    user-data = data.talos_machine_configuration.worker.machine_configuration
  }

  labels = {
    environment  = var.environment
    spot-instance = "true"
  }
}
```

**Spot Instance Best Practices:**

| Practice                       | Implementation                                                 |
| ------------------------------ | -------------------------------------------------------------- |
| **Diversify instance types**   | Use mixed instance policies (t3.xlarge, t3a.xlarge, m5.xlarge) |
| **Multi-AZ distribution**      | Spread workers across all AZs for interruption resilience      |
| **Graceful shutdown handling** | Engine/Control handle SIGTERM with 30s drain period            |
| **Capacity rebalancing**       | Enable `capacity-rebalancing` in ASG for proactive replacement |
| **On-demand fallback**         | Keep 1 on-demand worker per region as baseline                 |

```hcl
# terraform/modules/talos-cluster/asg-mixed.tf (AWS)
resource "aws_autoscaling_group" "workers_mixed" {
  count = var.provider_type == "aws" && var.use_spot_instances ? 1 : 0

  name                = "${var.cluster_name}-workers-mixed"
  desired_capacity    = var.worker_count
  min_size            = 1
  max_size            = var.worker_count * 2
  vpc_zone_identifier = var.subnet_ids

  # Mixed instances policy for spot + on-demand
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 1  # Always keep 1 on-demand
      on_demand_percentage_above_base_capacity = 0  # Rest are spot
      spot_allocation_strategy                 = "capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.worker_spot[0].id
        version            = "$Latest"
      }

      # Diversify instance types for better spot availability
      override {
        instance_type = "t3.xlarge"
      }
      override {
        instance_type = "t3a.xlarge"
      }
      override {
        instance_type = "m5.xlarge"
      }
      override {
        instance_type = "m5a.xlarge"
      }
    }
  }

  # Proactive capacity rebalancing
  capacity_rebalance = true

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 80
    }
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}
```

**Node Labels for Workload Scheduling:**

```yaml
# flux/infrastructure/base/node-labels/spot-labels.yaml
# Applied via Talos machine config or node labeler
# Workers get labeled based on instance lifecycle

# Stateless workloads tolerate spot interruptions
# flux/apps/base/engine/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-engine
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: node.kubernetes.io/lifecycle
                    operator: In
                    values:
                      - spot
                      - preemptible
      tolerations:
        - key: "spot-instance"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      # Match AWS 2-minute spot termination warning
      terminationGracePeriodSeconds: 120
```

**AWS Node Termination Handler:**

Deploy the Node Termination Handler to catch spot interruption warnings and proactively cordon/drain nodes before termination:

```yaml
# flux/infrastructure/base/controllers/aws-node-termination-handler/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: aws-node-termination-handler
  namespace: kube-system
spec:
  interval: 10m
  chart:
    spec:
      chart: aws-node-termination-handler
      version: "0.21.x"
      sourceRef:
        kind: HelmRepository
        name: eks
        namespace: flux-system
  values:
    # Spot interruption handling
    enableSpotInterruptionDraining: true
    # Proactive rebalancing when AWS signals capacity issues
    enableRebalanceMonitoring: true
    enableRebalanceDraining: true
    # Scheduled event handling (maintenance, etc.)
    enableScheduledEventDraining: true
    # Webhook for alerting
    webhookURL: "${SLACK_WEBHOOK_URL}"
    # Pod-level settings
    nodeTerminationGracePeriod: 120
    podTerminationGracePeriod: 90
    # Taint nodes during drain to prevent new pods
    taintNode: true
---
# HelmRepository for EKS charts
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: eks
  namespace: flux-system
spec:
  interval: 24h
  url: https://aws.github.io/eks-charts
```

**Spot Interruption Flow:**

```text
AWS Spot Interruption Warning (2 min before termination)
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Node Termination Handler (NTH)   │
    │  - Receives EC2 metadata event    │
    │  - Sends Slack/webhook alert      │
    └───────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  1. Cordon node (no new pods)     │
    │  2. Taint node (spot-terminating) │
    │  3. Drain pods gracefully         │
    └───────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  Pods migrate to other nodes      │
    │  (120s grace period)              │
    └───────────────────────────────────┘
                    │
                    ▼
    ┌───────────────────────────────────┐
    │  AWS terminates spot instance     │
    │  ASG launches replacement         │
    └───────────────────────────────────┘
```

---

## 6. Regional Cluster Provisioning Workflow

### Workflow Overview

```text
┌──────────────────────────────────────────────────────────────────┐
│                    New Region Provisioning                        │
└──────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ 1. Terraform  │    │ 2. Talos      │    │ 3. Flux       │
│    Provision  │───▶│    Bootstrap  │───▶│    Bootstrap  │
└───────────────┘    └───────────────┘    └───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
  - Cloud resources     - Generate configs    - Install Flux
  - VPC/Network         - Apply to nodes      - Bootstrap secrets
  - Load balancers      - Verify cluster      - Sync infrastructure
  - DNS records         - Install Cilium      - Deploy applications
  - Backup buckets      - Configure CNI
```

### Step-by-Step Process

#### Phase 1: Infrastructure Provisioning (Terraform)

```bash
# 1. Initialize new region from template
cp -r terraform/regions/_template terraform/regions/lon1

# 2. Configure region variables
# terraform/regions/lon1/variables.tf

# 3. Select provider and configure
cd terraform/environments/production
terraform init
terraform plan -var="region=lon1" -var="provider=aws"
terraform apply -var="region=lon1" -var="provider=aws"
```

#### Phase 2: Talos Bootstrap

```bash
# Generate Talos configs using talhelper (NOT --config-patch directly)
cd talos
talhelper genconfig --config-file talconfig.yaml --env-file .env.production

# Apply configs
talosctl apply-config --nodes <node-ips> --file ./clusterconfig/inferadb-production-lon1-controlplane-1.yaml
talosctl bootstrap --nodes <first-cp-ip>
talosctl kubeconfig --nodes <first-cp-ip> -f ./generated/production-lon1/kubeconfig

# Install Cilium (must be done before other workloads)
cilium install --helm-set ipam.mode=kubernetes
cilium status --wait
```

#### Phase 3: Flux Bootstrap

```bash
# Bootstrap secrets first
./scripts/bootstrap-secrets.sh production lon1

# Bootstrap Flux
flux bootstrap github \
  --owner=inferadb \
  --repository=inferadb-deploy \
  --branch=main \
  --path=./flux/clusters/prod-lon1 \
  --personal
```

### Automation Script

```bash
#!/bin/bash
# scripts/bootstrap-cluster.sh

set -euo pipefail

ENVIRONMENT=${1:-staging}
REGION=${2:-nyc1}
PROVIDER=${3:-aws}

echo "Bootstrapping ${ENVIRONMENT}/${REGION} on ${PROVIDER}"

# Phase 1: Terraform
cd terraform/environments/${ENVIRONMENT}
terraform init
terraform apply -var="region=${REGION}" -var="provider=${PROVIDER}" -auto-approve

# Extract outputs
CONTROL_PLANE_ENDPOINT=$(terraform output -raw control_plane_endpoint)
NODE_IPS=$(terraform output -json node_ips | jq -r '.[]')

# Phase 2: Talos (using talhelper)
cd ../../../talos
export TALOS_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
talhelper genconfig --config-file talconfig.yaml --env-file .env.${ENVIRONMENT}

for i in "${!NODE_IPS[@]}"; do
  talosctl apply-config --nodes ${NODE_IPS[$i]} \
    --file ./clusterconfig/inferadb-${ENVIRONMENT}-${REGION}-controlplane-$((i+1)).yaml
done

talosctl bootstrap --nodes ${NODE_IPS[0]}
sleep 30  # Wait for API server

# Install Cilium CNI
export KUBECONFIG=./clusterconfig/kubeconfig
cilium install --helm-set ipam.mode=kubernetes
cilium status --wait

# Phase 3: Flux
cd ..
./scripts/bootstrap-secrets.sh ${ENVIRONMENT} ${REGION}

flux bootstrap github \
  --owner=inferadb \
  --repository=inferadb-deploy \
  --branch=main \
  --path=./flux/clusters/${ENVIRONMENT}-${REGION}

echo "Cluster bootstrap complete for ${ENVIRONMENT}-${REGION}"
```

---

## 7. FoundationDB Deployment Pattern

### Critical: Latency Requirements for Multi-Region

**Issue**: The original plan proposed `three_datacenter` redundancy mode between NYC1 and SFO1. This requires synchronous replication with <50ms latency. NYC1 ↔ SFO1 latency is ~70ms, making synchronous replication impossible.

**Solution**: Use `three_data_hall` within a single region for HA, with asynchronous DR replication between regions.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                    NYC1 Region (Primary)                            │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              three_data_hall Configuration                   │    │
│  │                                                              │    │
│  │   Data Hall A        Data Hall B        Data Hall C         │    │
│  │   (AZ us-east-1a)    (AZ us-east-1b)    (AZ us-east-1c)    │    │
│  │   ┌──────────┐       ┌──────────┐       ┌──────────┐        │    │
│  │   │ Storage  │       │ Storage  │       │ Storage  │        │    │
│  │   │ Log      │       │ Log      │       │ Log      │        │    │
│  │   │ Stateless│       │ Stateless│       │ Stateless│        │    │
│  │   └──────────┘       └──────────┘       └──────────┘        │    │
│  │        │                  │                  │               │    │
│  │        └──────────────────┼──────────────────┘               │    │
│  │                           │                                  │    │
│  │                    Synchronous Replication                   │    │
│  │                    (<5ms latency within AZs)                 │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                      │
│                    Async DR Replication                             │
│                    (fdbdr tool, ~70ms latency)                      │
│                              │                                      │
└──────────────────────────────┼──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    SFO1 Region (DR Standby)                         │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              three_data_hall Configuration (Standby)         │    │
│  │              - Receives async replication                    │    │
│  │              - RPO: ~1-5 seconds                             │    │
│  │              - Can be promoted to primary                    │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### FoundationDB CRD (Not Helm Chart)

The FDB Kubernetes Operator uses Custom Resource Definitions directly, not a Helm chart:

```yaml
# flux/apps/base/foundationdb/foundationdbcluster.yaml
apiVersion: apps.foundationdb.org/v1beta2
kind: FoundationDBCluster
metadata:
  name: inferadb-fdb
  namespace: inferadb
spec:
  version: 7.3.43
  databaseConfiguration:
    redundancy_mode: three_data_hall
    storage_engine: ssd-2
    usable_regions: 1
  processCounts:
    storage: 5
    log: 5
    stateless: 5
    cluster_controller: 1
  processes:
    general:
      customParameters:
        - "knob_disable_posix_kernel_aio=1" # Required for some cloud providers
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd
          resources:
            requests:
              storage: 64Gi # Start conservative; expand online if needed
  routing:
    defineDNSLocalityFields: true
  faultDomain:
    key: topology.kubernetes.io/zone
    valueFrom: spec.nodeName
  mainContainer:
    imageType: split
  sidecarContainer:
    imageType: split
---
# flux/apps/base/foundationdb/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - foundationdbcluster.yaml
  - backup-cronjob.yaml
  - networkpolicy.yaml
```

### Backup Strategy

```yaml
# flux/apps/base/foundationdb/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: fdb-backup
  namespace: inferadb
spec:
  schedule: "0 * * * *" # Hourly
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: fdb-backup
          containers:
            - name: backup
              image: foundationdb/foundationdb:7.3.43
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail
                  BACKUP_URL="blobstore://${BACKUP_BUCKET}/${CLUSTER_NAME}/$(date +%Y%m%d-%H%M%S)"

                  # Start backup agent if not running
                  fdbbackup start -d "${BACKUP_URL}" -z || true

                  # Wait for backup to complete
                  fdbbackup wait -d "${BACKUP_URL}"

                  # Verify backup integrity
                  fdbbackup describe -d "${BACKUP_URL}"

                  # Clean up old backups (keep 7 days)
                  fdbbackup delete -d "blobstore://${BACKUP_BUCKET}/${CLUSTER_NAME}" \
                    --delete_before_days 7
              env:
                - name: FDB_CLUSTER_FILE
                  value: /var/fdb/data/fdb.cluster
                - name: BACKUP_BUCKET
                  valueFrom:
                    configMapKeyRef:
                      name: fdb-backup-config
                      key: bucket
                - name: CLUSTER_NAME
                  value: inferadb-fdb
              volumeMounts:
                - name: fdb-cluster-file
                  mountPath: /var/fdb/data
                - name: backup-credentials
                  mountPath: /var/secrets
          volumes:
            - name: fdb-cluster-file
              secret:
                secretName: inferadb-fdb-config
            - name: backup-credentials
              secret:
                secretName: fdb-backup-credentials
          restartPolicy: OnFailure
```

### Backup Restore Testing

Untested backups are Schrödinger's backups. Monthly restore validation ensures recoverability:

```yaml
# flux/apps/base/foundationdb/backup-restore-test.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: fdb-backup-restore-test
  namespace: inferadb
spec:
  schedule: "0 3 1 * *" # Monthly, 3 AM on the 1st
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      activeDeadlineSeconds: 7200 # 2 hour timeout
      template:
        spec:
          serviceAccountName: fdb-backup-test
          containers:
            - name: restore-test
              image: foundationdb/foundationdb:7.3.43
              command:
                - /bin/bash
                - -c
                - |
                  set -euo pipefail

                  echo "=== FDB Backup Restore Test Started ==="
                  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                  TEST_CLUSTER="restore-test-${TIMESTAMP}"

                  # Find latest backup
                  LATEST_BACKUP=$(fdbbackup list -d "blobstore://${BACKUP_BUCKET}/${SOURCE_CLUSTER}/" | \
                    grep -E '^[0-9]{8}' | sort -r | head -1)

                  if [ -z "$LATEST_BACKUP" ]; then
                    echo "ERROR: No backup found"
                    exit 1
                  fi

                  echo "Found backup: ${LATEST_BACKUP}"
                  BACKUP_URL="blobstore://${BACKUP_BUCKET}/${SOURCE_CLUSTER}/${LATEST_BACKUP}"

                  # Create ephemeral test cluster (single-node, in-memory)
                  echo "Creating ephemeral test cluster..."
                  fdbserver -p auto:4500 -C /tmp/test.cluster &
                  FDB_PID=$!
                  sleep 10

                  # Configure test cluster
                  fdbcli -C /tmp/test.cluster --exec "configure new single memory"

                  # Restore backup to test cluster
                  echo "Restoring backup to test cluster..."
                  fdbrestore start -r "${BACKUP_URL}" -C /tmp/test.cluster --dest-cluster-file /tmp/test.cluster

                  # Wait for restore to complete
                  fdbrestore wait -r "${BACKUP_URL}"

                  # Validate data integrity
                  echo "Validating restored data..."

                  # Check cluster health
                  HEALTH=$(fdbcli -C /tmp/test.cluster --exec "status json" | jq -r '.cluster.data.state.healthy')
                  if [ "$HEALTH" != "true" ]; then
                    echo "ERROR: Restored cluster is unhealthy"
                    kill $FDB_PID 2>/dev/null || true
                    exit 1
                  fi

                  # Verify key ranges exist
                  KEY_COUNT=$(fdbcli -C /tmp/test.cluster --exec "getrangekeys '' '\xff' 1000" | wc -l)
                  echo "Restored ${KEY_COUNT} key ranges"

                  if [ "$KEY_COUNT" -lt 1 ]; then
                    echo "ERROR: No data found in restored cluster"
                    kill $FDB_PID 2>/dev/null || true
                    exit 1
                  fi

                  # Cleanup
                  echo "Cleaning up test cluster..."
                  kill $FDB_PID 2>/dev/null || true

                  echo "=== Backup Restore Test PASSED ==="
                  echo "Backup: ${LATEST_BACKUP}"
                  echo "Keys verified: ${KEY_COUNT}"

                  # Send success metric to Prometheus pushgateway
                  cat <<METRIC | curl --data-binary @- http://prometheus-pushgateway:9091/metrics/job/fdb-backup-test
                  # HELP fdb_backup_restore_test_success Backup restore test result
                  # TYPE fdb_backup_restore_test_success gauge
                  fdb_backup_restore_test_success{cluster="${SOURCE_CLUSTER}"} 1
                  fdb_backup_restore_test_timestamp{cluster="${SOURCE_CLUSTER}"} $(date +%s)
                  fdb_backup_restore_test_keys{cluster="${SOURCE_CLUSTER}"} ${KEY_COUNT}
                  METRIC
              env:
                - name: FDB_CLUSTER_FILE
                  value: /var/fdb/data/fdb.cluster
                - name: BACKUP_BUCKET
                  valueFrom:
                    configMapKeyRef:
                      name: fdb-backup-config
                      key: bucket
                - name: SOURCE_CLUSTER
                  value: inferadb-fdb
              volumeMounts:
                - name: fdb-cluster-file
                  mountPath: /var/fdb/data
                - name: backup-credentials
                  mountPath: /var/secrets
                - name: tmp
                  mountPath: /tmp
              resources:
                requests:
                  cpu: 500m
                  memory: 2Gi
                limits:
                  cpu: 2
                  memory: 4Gi
          volumes:
            - name: fdb-cluster-file
              secret:
                secretName: inferadb-fdb-config
            - name: backup-credentials
              secret:
                secretName: fdb-backup-credentials
            - name: tmp
              emptyDir:
                medium: Memory
                sizeLimit: 2Gi
          restartPolicy: Never
```

```yaml
# alerts/prometheusrules/fdb-backup-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: fdb-backup-alerts
  namespace: monitoring
spec:
  groups:
    - name: fdb-backup
      rules:
        - alert: FDBBackupRestoreTestFailed
          expr: fdb_backup_restore_test_success == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "FDB backup restore test failed"
            description: "Monthly backup restore validation failed for {{ $labels.cluster }}"

        - alert: FDBBackupRestoreTestStale
          expr: time() - fdb_backup_restore_test_timestamp > 35 * 24 * 3600 # 35 days
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "FDB backup restore test is stale"
            description: "No backup restore test has run in over 35 days for {{ $labels.cluster }}"
```

### Backup Infrastructure (Terraform)

```hcl
# terraform/modules/fdb-backup/main.tf
resource "aws_s3_bucket" "fdb_backup" {
  bucket = "inferadb-fdb-backup-${var.environment}-${var.region}"

  tags = {
    Environment = var.environment
    Region      = var.region
    Purpose     = "fdb-backup"
  }
}

resource "aws_s3_bucket_versioning" "fdb_backup" {
  bucket = aws_s3_bucket.fdb_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "fdb_backup" {
  bucket = aws_s3_bucket.fdb_backup.id

  rule {
    id     = "cleanup-old-backups"
    status = "Enabled"

    expiration {
      days = 30  # Keep backups for 30 days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    transition {
      days          = 7
      storage_class = "GLACIER_IR"
    }
  }
}

# Cross-region replication for DR
resource "aws_s3_bucket_replication_configuration" "fdb_backup" {
  count  = var.enable_cross_region_replication ? 1 : 0
  bucket = aws_s3_bucket.fdb_backup.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-to-dr"
    status = "Enabled"

    destination {
      bucket        = var.dr_bucket_arn
      storage_class = "STANDARD"
    }
  }
}
```

### RPO/RTO Targets

| Scenario                  | RPO                  | RTO           | Strategy                      |
| ------------------------- | -------------------- | ------------- | ----------------------------- |
| **Single AZ failure**     | 0 (sync replication) | <30 seconds   | three_data_hall auto-recovery |
| **Regional failure**      | 1-5 seconds          | 5-15 minutes  | Async DR promotion            |
| **Data corruption**       | Last backup          | 30-60 minutes | Point-in-time restore         |
| **Complete cluster loss** | Last backup          | 2-4 hours     | Full restore from backup      |

### FDB Version Upgrade Strategy

```markdown
# runbooks/fdb-upgrade.md

## FoundationDB Version Upgrade Procedure

### Pre-Upgrade Checklist

- [ ] Verify current cluster health: `fdbcli --exec "status details"`
- [ ] Verify backup is current: `fdbcli --exec "status json" | jq '.cluster.backup'`
- [ ] Review release notes for breaking changes
- [ ] Test upgrade in staging environment first
- [ ] Schedule maintenance window (non-peak hours)
- [ ] Notify stakeholders

### Upgrade Steps

1. **Update Operator First**

   # Update the FDB operator to a version supporting the target FDB version

   flux reconcile helmrelease fdb-operator -n fdb-operator

2. **Rolling Upgrade via Operator**

   # Update the FoundationDBCluster spec

   spec:
   version: 7.3.47 # New version
   automationOptions:
   configureDatabase: true
   deletePods: true

3. **Monitor Upgrade Progress**
   kubectl get foundationdbcluster -n inferadb -w
   fdbcli --exec "status details"

4. **Verify Post-Upgrade**
   - Check all processes are running new version
   - Verify client compatibility
   - Run smoke tests against engine

### Rollback Procedure

FDB does not support version downgrades. If upgrade fails:

1. Restore from backup to a new cluster
2. Update DNS/service discovery to point to new cluster
3. Investigate root cause before retrying upgrade
```

---

## 8. Service Deployment Strategy

### Deployment Hierarchy

```text
flux/apps/
├── base/                    # Shared definitions
│   ├── engine/
│   │   ├── helmrelease.yaml
│   │   ├── configmap.yaml
│   │   ├── external-secret.yaml
│   │   ├── networkpolicy.yaml
│   │   └── kustomization.yaml
│   ├── control/
│   ├── dashboard/
│   └── kustomization.yaml
│
├── dev/                     # Development overrides
├── staging/{region}/        # Staging per-region overrides
└── production/{region}/     # Production per-region overrides
```

### Engine HelmRelease (Base)

```yaml
# flux/apps/base/engine/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: inferadb-engine
  namespace: inferadb
spec:
  interval: 10m
  chart:
    spec:
      chart: inferadb-engine
      version: "1.2.3" # Pinned version, never use 'latest'
      sourceRef:
        kind: HelmRepository
        name: inferadb
        namespace: flux-system
  valuesFrom:
    - kind: ConfigMap
      name: engine-config
      valuesKey: values.yaml
  values:
    replicaCount: 3
    image:
      repository: ghcr.io/inferadb/engine
      tag: "v1.2.3" # Pinned, managed by Flux ImageUpdateAutomation
      pullPolicy: IfNotPresent
    autoscaling:
      enabled: true
      minReplicas: 3
      maxReplicas: 20
    storage:
      backend: foundationdb
    discovery:
      mode: kubernetes
    tailscale:
      enabled: false
```

### Ingress Rate Limiting

For customer-facing APIs, implement rate limiting at the ingress level to prevent abuse:

```yaml
# flux/apps/base/engine/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: inferadb-engine
  namespace: inferadb
  annotations:
    # Cilium Ingress Controller
    kubernetes.io/ingress.class: cilium

    # Rate limiting annotations (if using nginx-ingress as alternative)
    # nginx.ingress.kubernetes.io/limit-rps: "100"
    # nginx.ingress.kubernetes.io/limit-connections: "50"
spec:
  rules:
    - host: api.inferadb.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: inferadb-engine
                port:
                  number: 8080
  tls:
    - hosts:
        - api.inferadb.io
      secretName: inferadb-api-tls
```

**Cilium L7 Rate Limiting Policy:**

```yaml
# policies/network-policies/production/engine-rate-limit.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: engine-rate-limit
  namespace: inferadb
spec:
  endpointSelector:
    matchLabels:
      app: inferadb-engine
  ingress:
    - fromEntities:
        - world # External traffic
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: "POST"
                path: "/api/v1/check"
                # L7 rate limiting per source IP
                # Note: Requires Cilium Envoy configuration
```

**Envoy Rate Limit Configuration (for Cilium L7):**

```yaml
# flux/infrastructure/production/rate-limit/envoy-ratelimit.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-ratelimit-config
  namespace: cilium
data:
  config.yaml: |
    domain: inferadb
    descriptors:
      # Global rate limit: 10,000 requests per second across all clients
      - key: generic_key
        value: global
        rate_limit:
          unit: second
          requests_per_unit: 10000

      # Per-IP rate limit: 100 requests per second per client
      - key: remote_address
        rate_limit:
          unit: second
          requests_per_unit: 100

      # Per-tenant rate limit: 1000 requests per second per vault
      - key: header_match
        value: x-vault-id
        rate_limit:
          unit: second
          requests_per_unit: 1000

      # Burst protection: max 50 concurrent requests per IP
      - key: remote_address
        rate_limit:
          unit: minute
          requests_per_unit: 3000  # 50/sec average
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ratelimit
  namespace: cilium
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ratelimit
  template:
    metadata:
      labels:
        app: ratelimit
    spec:
      containers:
        - name: ratelimit
          image: envoyproxy/ratelimit:v1.4.0
          ports:
            - containerPort: 8080
              name: http
            - containerPort: 8081
              name: grpc
          env:
            - name: USE_STATSD
              value: "false"
            - name: LOG_LEVEL
              value: "info"
            - name: REDIS_SOCKET_TYPE
              value: "tcp"
            - name: REDIS_URL
              value: "redis.cilium:6379"
            - name: RUNTIME_ROOT
              value: "/data"
            - name: RUNTIME_SUBDIRECTORY
              value: "ratelimit"
          volumeMounts:
            - name: config
              mountPath: /data/ratelimit/config
      volumes:
        - name: config
          configMap:
            name: envoy-ratelimit-config
---
# Redis backend for rate limiting state
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: cilium
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          emptyDir: {} # Use PVC for persistence in production
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: cilium
spec:
  ports:
    - port: 6379
      targetPort: 6379
  selector:
    app: redis
```

**Rate Limit Response Headers:**

```yaml
# Clients receive these headers to understand their rate limit status
# X-RateLimit-Limit: 100
# X-RateLimit-Remaining: 95
# X-RateLimit-Reset: 1640000000
# Retry-After: 60 (when rate limited)
```

**Rate Limiting Alerts:**

```yaml
# alerts/prometheusrules/ratelimit-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: ratelimit-alerts
  namespace: monitoring
spec:
  groups:
    - name: rate-limiting
      rules:
        - alert: HighRateLimitHits
          expr: sum(rate(envoy_ratelimit_over_limit_total[5m])) > 100
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High rate of rate-limited requests"
            description: "{{ $value }} requests/sec are being rate limited"

        - alert: RateLimitServiceDown
          expr: up{job="ratelimit"} == 0
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Rate limit service is down"
            description: "Rate limiting is not functioning - potential for abuse"
```

### Dashboard Deployment (Base) - Fixed Image Tag

```yaml
# flux/apps/base/dashboard/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inferadb-dashboard
  namespace: inferadb
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inferadb-dashboard
  template:
    metadata:
      labels:
        app: inferadb-dashboard
    spec:
      containers:
        - name: dashboard
          image: ghcr.io/inferadb/dashboard:v1.2.3 # Pinned version
          ports:
            - containerPort: 3000
          env:
            - name: VITE_API_URL
              value: "http://inferadb-control:8080"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

---

## 9. CI/CD Integration

### Image Tagging Strategy

```text
ghcr.io/inferadb/engine:v1.2.3           # Semver release tag
ghcr.io/inferadb/engine:v1.2.3-abc1234   # Semver + git SHA (for traceability)
ghcr.io/inferadb/engine:main-abc1234     # Branch + SHA (for staging)
```

### Flux Image Automation

```yaml
# flux/apps/base/engine/image-policy.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: engine
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: engine
  filterTags:
    pattern: '^v(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)$'
    extract: "$major.$minor.$patch"
  policy:
    semver:
      range: ">=1.0.0"
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: engine
  namespace: flux-system
spec:
  image: ghcr.io/inferadb/engine
  interval: 5m
  secretRef:
    name: ghcr-credentials
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata:
  name: inferadb-apps
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: inferadb-deploy
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        name: fluxbot
        email: flux@inferadb.io
      messageTemplate: |
        chore: update images

        {{ range .Updated.Images }}
        - {{ .Repository }}:{{ .PreviousTag }} -> {{ .NewTag }}
        {{ end }}
    push:
      branch: main
  update:
    path: ./flux/apps
    strategy: Setters
```

### Rollback Procedures

```yaml
# Immediate rollback via Flux
# Option 1: Suspend automation and manually set tag
flux suspend imageupdate inferadb-apps
kubectl set image deployment/inferadb-engine engine=ghcr.io/inferadb/engine:v1.2.2 -n inferadb

# Option 2: Revert git commit and reconcile
git revert HEAD
git push
flux reconcile kustomization apps-production-nyc1 --with-source

# Option 3: Use HelmRelease rollback
flux suspend helmrelease inferadb-engine -n inferadb
helm rollback inferadb-engine 1 -n inferadb
```

### Progressive Delivery with Flagger

For production deployments, use Flagger with Cilium's traffic shifting to reduce blast radius on bad deploys:

```yaml
# flux/infrastructure/base/controllers/flagger/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: flagger
  namespace: flagger-system
spec:
  interval: 10m
  chart:
    spec:
      chart: flagger
      version: "1.x.x"
      sourceRef:
        kind: HelmRepository
        name: flagger
        namespace: flux-system
  values:
    meshProvider: kubernetes
    metricsServer: http://prometheus.monitoring:9090
    # Use Cilium for traffic shifting
    ingressAnnotations:
      kubernetes.io/ingress.class: cilium
```

```yaml
# flux/apps/production/engine/canary.yaml
# NOTE: Flagger + Cilium L7 is less battle-tested than Flagger + Istio.
# Test thoroughly in staging before production use.
# Alternative: Use Gateway API with Cilium for traffic splitting.
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: inferadb-engine
  namespace: inferadb
spec:
  # Provider mode for Kubernetes-native traffic splitting
  # This uses ClusterIP services instead of a service mesh
  provider: kubernetes
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: inferadb-engine
  # Service configuration
  service:
    port: 8080
    targetPort: 8080
    # Apex service (stable endpoint for clients)
    apex:
      annotations:
        prometheus.io/scrape: "true"
    # Canary service annotations
    canary:
      annotations:
        prometheus.io/scrape: "true"
  # Analysis configuration
  analysis:
    # Check interval
    interval: 1m
    # Max failed checks before rollback
    threshold: 5
    # Max traffic percentage routed to canary (Kubernetes provider uses replica scaling)
    maxWeight: 50
    # Canary increment step
    stepWeight: 10
    # Prometheus metrics for analysis
    metrics:
      - name: request-success-rate
        # Custom metric template for Kubernetes provider
        templateRef:
          name: request-success-rate
          namespace: flagger-system
        thresholdRange:
          min: 99
        interval: 1m
      - name: request-duration
        templateRef:
          name: request-duration
          namespace: flagger-system
        thresholdRange:
          max: 200 # milliseconds
        interval: 1m
    # Load testing during canary analysis
    webhooks:
      - name: load-test
        type: rollout
        url: http://flagger-loadtester.flagger-system/
        metadata:
          cmd: "hey -z 1m -q 10 -c 2 http://inferadb-engine-canary.inferadb:8080/healthz"
  # Progressive traffic shifting
  progressDeadlineSeconds: 600
  # Skip analysis for first deployment
  skipAnalysis: false
---
# Metric templates for Kubernetes provider mode
apiVersion: flagger.app/v1beta1
kind: MetricTemplate
metadata:
  name: request-success-rate
  namespace: flagger-system
spec:
  provider:
    type: prometheus
    address: http://prometheus.monitoring:9090
  query: |
    sum(rate(
      http_requests_total{
        namespace="{{ namespace }}",
        deployment=~"{{ target }}-[0-9a-zA-Z]+(-[0-9a-zA-Z]+)",
        status!~"5.*"
      }[{{ interval }}]
    )) /
    sum(rate(
      http_requests_total{
        namespace="{{ namespace }}",
        deployment=~"{{ target }}-[0-9a-zA-Z]+(-[0-9a-zA-Z]+)"
      }[{{ interval }}]
    )) * 100
---
apiVersion: flagger.app/v1beta1
kind: MetricTemplate
metadata:
  name: request-duration
  namespace: flagger-system
spec:
  provider:
    type: prometheus
    address: http://prometheus.monitoring:9090
  query: |
    histogram_quantile(0.99,
      sum(rate(
        http_request_duration_seconds_bucket{
          namespace="{{ namespace }}",
          deployment=~"{{ target }}-[0-9a-zA-Z]+(-[0-9a-zA-Z]+)"
        }[{{ interval }}]
      )) by (le)
    ) * 1000
```

### Alternative: Gateway API with Cilium

If Flagger's Kubernetes provider doesn't meet your needs, consider using Gateway API directly with Cilium for more robust traffic splitting (recommended for production):

```yaml
# Using Gateway API HTTPRoute for traffic splitting
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: inferadb-engine-canary
  namespace: inferadb
spec:
  parentRefs:
    - name: cilium-gateway
      namespace: cilium
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: inferadb-engine-primary
          port: 8080
          weight: 90
        - name: inferadb-engine-canary
          port: 8080
          weight: 10
```

**Canary Deployment Flow:**

```text
┌─────────────────────────────────────────────────────────────────────┐
│                    Progressive Delivery Flow                         │
└─────────────────────────────────────────────────────────────────────┘

1. New image detected by Flux ImageUpdateAutomation
2. Flagger creates canary deployment (inferadb-engine-canary)
3. Traffic split: 100% primary, 0% canary

Step 1: 90% primary, 10% canary
  │
  ├── Metrics check: success rate >= 99%? latency < 200ms?
  │   ├── YES → Continue to next step
  │   └── NO → Rollback to primary
  │
Step 2: 80% primary, 20% canary
  │
  ├── Metrics check...
  │
Step 3-5: Gradual increase to 50% canary
  │
Final: Promote canary to primary, scale down old primary
```

**Flagger Alerts:**

```yaml
# alerts/prometheusrules/flagger-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: flagger-alerts
  namespace: monitoring
spec:
  groups:
    - name: flagger
      rules:
        - alert: CanaryAnalysisFailed
          expr: flagger_canary_status{status="failed"} == 1
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Canary deployment failed for {{ $labels.name }}"
            description: "Canary {{ $labels.name }} in {{ $labels.namespace }} failed analysis and was rolled back"

        - alert: CanaryStuck
          expr: flagger_canary_status{status="progressing"} == 1 and time() - flagger_canary_timestamp > 1800
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Canary deployment stuck for {{ $labels.name }}"
            description: "Canary {{ $labels.name }} has been progressing for over 30 minutes"
```

---

## 10. Observability Stack

### Observability Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                     Observability Stack                              │
│                                                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐    │
│  │   Metrics  │  │    Logs    │  │   Traces   │  │   Alerts   │    │
│  │            │  │            │  │            │  │            │    │
│  │ Prometheus │  │    Loki    │  │   Tempo    │  │AlertManager│    │
│  │   + Thanos │  │            │  │            │  │            │    │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘    │
│        │               │               │               │            │
│        └───────────────┴───────────────┴───────────────┘            │
│                              │                                       │
│                        ┌─────▼─────┐                                │
│                        │  Grafana  │                                │
│                        │ (unified) │                                │
│                        └───────────┘                                │
└─────────────────────────────────────────────────────────────────────┘
```

### Log Aggregation (Critical for Talos)

Since Talos has no SSH, centralized logging is essential:

```yaml
# flux/infrastructure/base/controllers/loki/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: loki
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: loki
      version: "5.x.x"
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    loki:
      auth_enabled: false
      storage:
        type: s3
        s3:
          endpoint: s3.amazonaws.com
          bucketnames: inferadb-logs-${REGION}
          region: ${AWS_REGION}
    gateway:
      enabled: true
---
# Promtail for log collection
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: promtail
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: promtail
      version: "6.x.x"
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    config:
      clients:
        - url: http://loki-gateway/loki/api/v1/push
      snippets:
        extraScrapeConfigs: |
          # Talos system logs via journal
          - job_name: talos-system
            journal:
              max_age: 12h
              labels:
                job: talos-system
            relabel_configs:
              - source_labels: ['__journal__systemd_unit']
                target_label: 'unit'
```

### Distributed Tracing

```yaml
# flux/infrastructure/base/controllers/tempo/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tempo
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: tempo
      version: "1.x.x"
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    tempo:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "0.0.0.0:4317"
            http:
              endpoint: "0.0.0.0:4318"
    storage:
      trace:
        backend: s3
        s3:
          bucket: inferadb-traces-${REGION}
```

### Prometheus Pushgateway

Required for batch job metrics (backup restore tests, etc.):

```yaml
# flux/infrastructure/base/controllers/pushgateway/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: prometheus-pushgateway
  namespace: monitoring
spec:
  interval: 10m
  chart:
    spec:
      chart: prometheus-pushgateway
      version: "2.x.x"
      sourceRef:
        kind: HelmRepository
        name: prometheus-community
        namespace: flux-system
  values:
    serviceMonitor:
      enabled: true
    persistentVolume:
      enabled: false # Metrics are ephemeral
    resources:
      requests:
        cpu: 50m
        memory: 32Mi
      limits:
        cpu: 100m
        memory: 64Mi
```

### FDB Metrics Export

The FDB Operator exposes limited metrics. For comprehensive monitoring, deploy the FDB Prometheus exporter:

```yaml
# flux/infrastructure/base/controllers/fdb-exporter/deployment.yaml
# Note: Apple doesn't publish an official exporter. Using tigrisdata/fdb-exporter
# https://github.com/tigrisdata/fdb-prometheus-exporter
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fdb-prometheus-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fdb-prometheus-exporter
  template:
    metadata:
      labels:
        app: fdb-prometheus-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      containers:
        - name: exporter
          image: tigrisdata/fdb-exporter:v0.3.0 # Pin to specific version
          ports:
            - containerPort: 8080
              name: metrics
          args:
            - --fdb.cluster-file=/var/fdb/data/fdb.cluster
            - --web.listen-address=:8080
          volumeMounts:
            - name: fdb-cluster-file
              mountPath: /var/fdb/data
              readOnly: true
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
      volumes:
        - name: fdb-cluster-file
          secret:
            secretName: inferadb-fdb-config
---
apiVersion: v1
kind: Service
metadata:
  name: fdb-prometheus-exporter
  namespace: monitoring
  labels:
    app: fdb-prometheus-exporter
spec:
  ports:
    - port: 8080
      targetPort: 8080
      name: metrics
  selector:
    app: fdb-prometheus-exporter
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fdb-prometheus-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: fdb-prometheus-exporter
  endpoints:
    - port: metrics
      interval: 15s
      scrapeTimeout: 10s
```

**Metrics Verification (Required in Phase 2):**

Different FDB exporters use different metric naming conventions. After deploying, verify actual metric names match your alert expressions:

```bash
# Port-forward to the exporter pod
kubectl port-forward -n monitoring deploy/fdb-prometheus-exporter 8080:8080

# Check available metrics and their exact names
curl -s localhost:8080/metrics | grep -E '^fdb_|^foundationdb_' | head -30

# Example output might show:
# foundationdb_cluster_healthy 1
# foundationdb_storage_used_bytes{...} 12345678
# etc.
```

**Expected Metrics (verify against actual output):**

| Metric (naming may vary)                                      | Description                    |
| ------------------------------------------------------------- | ------------------------------ |
| `fdb_cluster_health` or `foundationdb_cluster_healthy`        | Cluster health status          |
| `fdb_storage_used_bytes` or `foundationdb_storage_used_bytes` | Storage bytes used             |
| `fdb_storage_capacity_bytes`                                  | Storage capacity per process   |
| `fdb_transactions_started_total`                              | Total transactions started     |
| `fdb_transactions_committed_total`                            | Total transactions committed   |
| `fdb_transactions_conflicted_total`                           | Total transaction conflicts    |
| `fdb_log_queue_depth` or `foundationdb_log_queue_length`      | Transaction log queue depth    |
| `fdb_cluster_recovering`                                      | Whether cluster is in recovery |

**Important:** After verification, update alert expressions in `alerts/prometheusrules/fdb-alerts.yaml` to match actual metric names from your exporter version. The alerts below use assumed metric names—adjust as needed.

### FDB-Specific Alerts

```yaml
# alerts/prometheusrules/fdb-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: fdb-alerts
  namespace: monitoring
spec:
  groups:
    - name: foundationdb
      rules:
        # Cluster health
        - alert: FDBClusterDegraded
          expr: fdb_cluster_health < 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "FoundationDB cluster is degraded"
            description: "Cluster {{ $labels.cluster }} health is {{ $value }}"

        # Storage utilization
        - alert: FDBStorageNearCapacity
          expr: fdb_storage_used_bytes / fdb_storage_capacity_bytes > 0.8
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "FDB storage usage above 80%"

        # Transaction conflicts
        - alert: FDBHighConflictRate
          expr: rate(fdb_transactions_conflicted_total[5m]) > 100
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High transaction conflict rate detected"
            description: "{{ $value }} conflicts/sec on {{ $labels.cluster }}"

        # Log queue
        - alert: FDBLogQueueBacklog
          expr: fdb_log_queue_depth > 1000000
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "FDB log queue backlog building"

        # Recovery
        - alert: FDBRecoveryInProgress
          expr: fdb_cluster_recovering == 1
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "FDB cluster recovery taking too long"
```

### Engine Alerts

```yaml
# alerts/prometheusrules/engine-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: engine-alerts
  namespace: monitoring
spec:
  groups:
    - name: inferadb-engine
      rules:
        - alert: EngineHighLatency
          expr: histogram_quantile(0.99, rate(inferadb_engine_request_duration_seconds_bucket[5m])) > 0.5
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Engine p99 latency above 500ms"

        - alert: EngineHighErrorRate
          expr: rate(inferadb_engine_errors_total[5m]) / rate(inferadb_engine_requests_total[5m]) > 0.01
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Engine error rate above 1%"

        - alert: EnginePodNotReady
          expr: kube_pod_status_ready{namespace="inferadb", pod=~"inferadb-engine.*"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Engine pod not ready"
```

---

## 11. Tailscale Mesh Configuration

### Mesh Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         Tailscale Mesh                               │
│                                                                      │
│  ┌──────────────────┐              ┌──────────────────┐             │
│  │    NYC1 Cluster  │◄────────────►│    SFO1 Cluster  │             │
│  │                  │   Tailscale  │                  │             │
│  │  ┌────────────┐  │    WireGuard │  ┌────────────┐  │             │
│  │  │   Engine   │  │              │  │   Engine   │  │             │
│  │  │  (Sidecar) │  │              │  │  (Sidecar) │  │             │
│  │  └────────────┘  │              │  └────────────┘  │             │
│  │                  │              │                  │             │
│  │  ┌────────────┐  │              │  ┌────────────┐  │             │
│  │  │    FDB     │  │              │  │    FDB     │  │             │
│  │  │  (Router)  │  │              │  │  (Router)  │  │             │
│  │  └────────────┘  │              │  └────────────┘  │             │
│  └──────────────────┘              └──────────────────┘             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Tailscale Operator Deployment

```yaml
# flux/infrastructure/base/controllers/tailscale-operator/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: tailscale-operator
  namespace: tailscale
spec:
  interval: 10m
  chart:
    spec:
      chart: tailscale-operator
      version: "1.x.x"
      sourceRef:
        kind: HelmRepository
        name: tailscale
        namespace: flux-system
  values:
    oauth:
      clientId: ${TAILSCALE_CLIENT_ID}
      clientSecret: ${TAILSCALE_CLIENT_SECRET}
```

---

## 12. Scaling and Failover Considerations

### Horizontal Pod Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
  customMetrics:
    - type: Pods
      pods:
        metric:
          name: inferadb_requests_per_second
        target:
          type: AverageValue
          averageValue: "1000"
```

### PodDisruptionBudgets

Prevent accidental service disruption during node drains and cluster upgrades:

```yaml
# flux/apps/base/engine/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: inferadb-engine-pdb
  namespace: inferadb
spec:
  # Ensure at least 80% of pods remain available during disruption
  minAvailable: "80%"
  selector:
    matchLabels:
      app: inferadb-engine
---
# flux/apps/base/control/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: inferadb-control-pdb
  namespace: inferadb
spec:
  # Use maxUnavailable instead of minAvailable to allow rolling updates
  # when running at minimum replica count (2)
  maxUnavailable: 1
  selector:
    matchLabels:
      app: inferadb-control
---
# flux/apps/base/foundationdb/pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fdb-storage-pdb
  namespace: inferadb
spec:
  # FDB storage: allow only 1 disruption at a time to maintain quorum
  maxUnavailable: 1
  selector:
    matchLabels:
      app: foundationdb
      fdb-process-class: storage
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fdb-log-pdb
  namespace: inferadb
spec:
  # FDB logs: critical for writes, allow only 1 disruption
  maxUnavailable: 1
  selector:
    matchLabels:
      app: foundationdb
      fdb-process-class: log
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: fdb-stateless-pdb
  namespace: inferadb
spec:
  # Stateless processes are more resilient
  minAvailable: "50%"
  selector:
    matchLabels:
      app: foundationdb
      fdb-process-class: stateless
```

**PDB Strategy:**

| Component         | Strategy          | Rationale                                   |
| ----------------- | ----------------- | ------------------------------------------- |
| **Engine**        | minAvailable: 80% | High traffic tolerance, gradual disruption  |
| **Control**       | maxUnavailable: 1 | Allows rolling updates at min replica count |
| **FDB Storage**   | maxUnavailable: 1 | Quorum-based, one at a time                 |
| **FDB Log**       | maxUnavailable: 1 | Critical for writes                         |
| **FDB Stateless** | minAvailable: 50% | More resilient to disruption                |

### Regional Failover Strategy (Updated with Health-Check DNS)

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Regional Failover Flow                        │
└─────────────────────────────────────────────────────────────────┘

Normal Operation:
  Client ──► DNS (health-check routing) ──► NYC1 (primary)
                                          ──► SFO1 (standby)

NYC1 Failure Detected:
  1. Health checks fail (3 consecutive, 10s intervals)
  2. DNS immediately routes to SFO1 (no TTL wait)
  3. FDB DR cluster promoted to primary

  Client ──► DNS (health-check routing) ──► SFO1 (now primary)

Key Improvements:
  - Health-check based DNS (Route53/Cloud DNS) instead of TTL-based
  - 30-second detection vs 60-second TTL
  - Async FDB replication with 1-5 second RPO
```

### DNS Configuration (Health-Check Based)

```hcl
# terraform/modules/dns/main.tf
resource "aws_route53_health_check" "nyc1" {
  fqdn              = "api-nyc1.inferadb.io"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/healthz"
  failure_threshold = "3"
  request_interval  = "10"

  tags = {
    Name = "inferadb-nyc1-health"
  }
}

resource "aws_route53_record" "api" {
  zone_id = var.zone_id
  name    = "api.inferadb.io"
  type    = "A"

  set_identifier = "nyc1"
  health_check_id = aws_route53_health_check.nyc1.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.nyc1_lb_dns
    zone_id                = var.nyc1_lb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api_secondary" {
  zone_id = var.zone_id
  name    = "api.inferadb.io"
  type    = "A"

  set_identifier = "sfo1"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.sfo1_lb_dns
    zone_id                = var.sfo1_lb_zone_id
    evaluate_target_health = true
  }
}
```

---

## 13. SLOs and SLAs

### Service Level Objectives

```yaml
# slos/engine-slos.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: inferadb-engine-slo
  namespace: monitoring
spec:
  service: "inferadb-engine"
  labels:
    team: platform
  slos:
    # Availability SLO: 99.9% uptime
    - name: "availability"
      objective: 99.9
      description: "Engine API availability"
      sli:
        events:
          errorQuery: sum(rate(inferadb_engine_requests_total{status=~"5.."}[{{.window}}]))
          totalQuery: sum(rate(inferadb_engine_requests_total[{{.window}}]))
      alerting:
        name: EngineAvailabilityBudgetBurn
        labels:
          category: availability
        pageAlert:
          labels:
            severity: critical
        ticketAlert:
          labels:
            severity: warning

    # Latency SLO: 99% of requests < 200ms
    - name: "latency"
      objective: 99
      description: "Engine API latency p99 < 200ms"
      sli:
        events:
          errorQuery: sum(rate(inferadb_engine_request_duration_seconds_bucket{le="0.2"}[{{.window}}]))
          totalQuery: sum(rate(inferadb_engine_request_duration_seconds_count[{{.window}}]))
      alerting:
        name: EngineLatencyBudgetBurn
        labels:
          category: latency
```

### SLO Definitions

| Service             | SLI                            | SLO Target   | Error Budget (30 days) |
| ------------------- | ------------------------------ | ------------ | ---------------------- |
| **Engine API**      | Successful responses (non-5xx) | 99.9%        | 43.2 minutes           |
| **Engine API**      | p99 latency < 200ms            | 99%          | 7.2 hours              |
| **Control API**     | Successful responses (non-5xx) | 99.9%        | 43.2 minutes           |
| **FDB Cluster**     | Read availability              | 99.99%       | 4.32 minutes           |
| **FDB Cluster**     | Write availability             | 99.9%        | 43.2 minutes           |
| **Cross-region DR** | RPO (data loss window)         | < 5 seconds  | N/A                    |
| **Cross-region DR** | RTO (recovery time)            | < 15 minutes | N/A                    |

---

## 14. Testing Strategy

### Chaos Engineering

```bash
#!/bin/bash
# scripts/chaos/network-partition.sh
# Simulates network partition between regions using Cilium

set -euo pipefail

ACTION=${1:-create}  # create or delete
SOURCE_REGION=${2:-nyc1}
TARGET_REGION=${3:-sfo1}

if [ "$ACTION" == "create" ]; then
  echo "Creating network partition: ${SOURCE_REGION} -> ${TARGET_REGION}"

  kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: chaos-partition-${SOURCE_REGION}-${TARGET_REGION}
  namespace: inferadb
spec:
  endpointSelector:
    matchLabels:
      region: ${SOURCE_REGION}
  egressDeny:
    - toEndpoints:
        - matchLabels:
            region: ${TARGET_REGION}
EOF

  echo "Partition created. Monitor with: kubectl get cnp -n inferadb"

elif [ "$ACTION" == "delete" ]; then
  echo "Removing network partition"
  kubectl delete cnp chaos-partition-${SOURCE_REGION}-${TARGET_REGION} -n inferadb
fi
```

```bash
#!/bin/bash
# scripts/chaos/fdb-process-kill.sh
# Kills random FDB process to test recovery

set -euo pipefail

NAMESPACE=${1:-inferadb}
PROCESS_TYPE=${2:-storage}  # storage, log, or stateless

# Get random pod of the specified type
POD=$(kubectl get pods -n ${NAMESPACE} -l "app=foundationdb,fdb-process-class=${PROCESS_TYPE}" \
  -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | shuf -n 1)

echo "Killing FDB ${PROCESS_TYPE} process in pod: ${POD}"

# Kill the fdbserver process (container will restart)
kubectl exec -n ${NAMESPACE} ${POD} -- pkill -9 fdbserver

echo "Process killed. Monitor recovery with: fdbcli --exec 'status details'"
```

### Load Testing

```javascript
// load-tests/k6/engine-check.js
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const errorRate = new Rate("errors");
const checkLatency = new Trend("check_latency");

export const options = {
  stages: [
    { duration: "2m", target: 100 }, // Ramp up
    { duration: "5m", target: 100 }, // Steady state
    { duration: "2m", target: 200 }, // Spike
    { duration: "5m", target: 200 }, // Sustained spike
    { duration: "2m", target: 0 }, // Ramp down
  ],
  thresholds: {
    http_req_duration: ["p(99)<200"], // p99 < 200ms
    errors: ["rate<0.01"], // Error rate < 1%
  },
};

export default function () {
  const url = `${__ENV.ENGINE_URL}/api/v1/check`;
  const payload = JSON.stringify({
    vault_id: "test-vault",
    subject: { type: "user", id: "user-123" },
    permission: "read",
    object: { type: "document", id: "doc-456" },
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${__ENV.API_TOKEN}`,
    },
  };

  const start = Date.now();
  const res = http.post(url, payload, params);
  const duration = Date.now() - start;

  checkLatency.add(duration);

  const success = check(res, {
    "status is 200": (r) => r.status === 200,
    "response has allowed field": (r) =>
      JSON.parse(r.body).allowed !== undefined,
  });

  errorRate.add(!success);
  sleep(0.1);
}
```

### Running Load Tests

```bash
# Run against staging
k6 run --env ENGINE_URL=https://api.staging.inferadb.io \
       --env API_TOKEN=$(cat /path/to/token) \
       load-tests/k6/engine-check.js

# Output results to InfluxDB for visualization
k6 run --out influxdb=http://influxdb:8086/k6 \
       --env ENGINE_URL=https://api.staging.inferadb.io \
       load-tests/k6/engine-check.js
```

---

## 15. Cost and Resource Management

### Cost Estimation (Monthly) — Optimized

| Component                                    | Staging (NYC1 only) | Production (NYC1+SFO1) |
| -------------------------------------------- | ------------------- | ---------------------- |
| **Compute (Talos nodes)**                    |                     |                        |
| - Control Plane (3x t3.medium)               | $125                | $250 (2 regions)       |
| - Workers On-Demand (1x t3.xlarge baseline)  | $125                | $250 (1 per region)    |
| - Workers Spot (2x t3.xlarge @ 70% discount) | $75                 | $360 (4x per region)   |
| **FoundationDB Storage**                     |                     |                        |
| - 3-node cluster x 64GB (start small)        | $40                 | $200 (5-node x 2)      |
| **Networking**                               |                     |                        |
| - Cross-region transfer (~100GB/month)       | $0 (single region)  | $200                   |
| - Load Balancers (2)                         | $40                 | $80 (2 regions)        |
| **Storage**                                  |                     |                        |
| - FDB backups (S3, 500GB)                    | $15                 | $50                    |
| - Logs (Loki, 200GB)                         | $10                 | $30                    |
| - Traces (Tempo, 100GB)                      | $5                  | $15                    |
| **Tailscale**                                |                     |                        |
| - Business plan                              | $0                  | $180                   |
| **Monitoring**                               |                     |                        |
| - Prometheus/Grafana (self-hosted)           | $0                  | $0                     |
|                                              |                     |                        |
| **Total (On-Demand)**                        | **~$435/month**     | **~$1,615/month**      |
| **Total (with 1-year RI/SP on baseline)**    | **~$380/month**     | **~$1,400/month**      |

**Cost Optimization Summary:**

| Strategy                    | Staging Savings | Production Savings |
| --------------------------- | --------------- | ------------------ |
| Single-region staging       | ~$515/mo (50%)  | N/A                |
| Spot instances for workers  | ~$125/mo        | ~$480/mo           |
| Smaller FDB storage (64GB)  | ~$70/mo         | ~$160/mo           |
| Reserved Instances (1-year) | ~$55/mo         | ~$215/mo           |
| **Total vs Original**       | **$595/mo**     | **$790/mo**        |

Notes:

- Prices based on AWS us-east-1 pricing (December 2024)
- Spot pricing assumes 70% average discount; actual varies by instance type/AZ
- FDB storage can be expanded online if 64GB proves insufficient
- Monthly DR drills add ~$50/drill for staging (4-8 hours of temporary infra)

### Reserved Instances & Savings Plans Strategy

For predictable baseline capacity, purchase commitments reduce costs 30-50%:

**Recommended Commitments (Production):**

| Resource Type                   | Commitment           | Term               | Savings | Monthly Cost |
| ------------------------------- | -------------------- | ------------------ | ------- | ------------ |
| Control Plane (6x t3.medium)    | Reserved Instance    | 1-year, No Upfront | 31%     | $173 → $119  |
| Baseline Workers (2x t3.xlarge) | Compute Savings Plan | 1-year             | 36%     | $250 → $160  |
| FDB Storage (EBS gp3)           | N/A                  | Pay-as-you-go      | -       | $200         |

**AWS Savings Plan vs Reserved Instances:**

| Aspect             | EC2 Reserved Instance           | Compute Savings Plan            |
| ------------------ | ------------------------------- | ------------------------------- |
| **Flexibility**    | Locked to instance type/region  | Any instance type/region/OS     |
| **Discount**       | Up to 72% (3-year, all upfront) | Up to 66% (3-year, all upfront) |
| **Best For**       | Control plane (predictable)     | Workers (may resize)            |
| **Recommendation** | Control plane nodes             | Baseline worker capacity        |

**Implementation Steps:**

```bash
# 1. Wait 30-60 days after production launch to analyze usage patterns
# 2. Use AWS Cost Explorer to see Savings Plan recommendations:
aws ce get-savings-plans-purchase-recommendation \
  --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR \
  --payment-option NO_UPFRONT \
  --lookback-period-in-days THIRTY_DAYS

# 3. Review instance usage for RI recommendations:
aws ce get-reservation-purchase-recommendation \
  --service "Amazon Elastic Compute Cloud - Compute" \
  --lookback-period-in-days THIRTY_DAYS

# 4. Purchase via AWS Console or CLI after review
```

**GCP Equivalent (Committed Use Discounts):**

```bash
# GCP offers 1-year (37%) or 3-year (55%) committed use discounts
# Commit to vCPUs and memory, flexible across machine types

gcloud compute commitments create inferadb-production \
  --region=us-east4 \
  --plan=12-month \
  --resources=vcpu=16,memory=64GB
```

**When to Commit:**

- ✅ After 30-60 days of stable production usage
- ✅ Control plane nodes (always running, predictable)
- ✅ On-demand baseline workers (1 per region)
- ❌ Spot instance capacity (already discounted)
- ❌ FDB storage (may need to expand)
- ❌ Staging environment (may tear down)

### Cost Alerting

Configure AWS Budgets to alert on unexpected spend:

```yaml
# flux/infrastructure/production/cost-alerts/aws-budget.yaml
# Applied via Terraform, shown here for documentation

# terraform/modules/cost-alerts/main.tf
resource "aws_budgets_budget" "inferadb_monthly" {
  name              = "inferadb-production-monthly"
  budget_type       = "COST"
  limit_amount      = "2000"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$InferaDB",
      "user:Environment$production"
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["platform-team@inferadb.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["platform-team@inferadb.com", "oncall@inferadb.com"]
  }
}

resource "aws_budgets_budget" "spot_interruption_spike" {
  name              = "inferadb-spot-interruption-costs"
  budget_type       = "COST"
  limit_amount      = "500"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  # Track when spot interruptions cause on-demand fallback
  cost_filter {
    name = "TagKeyValue"
    values = ["user:InstanceLifecycle$on-demand"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["platform-team@inferadb.com"]
  }
}
```

**Kubernetes-Level Cost Monitoring with OpenCost:**

```yaml
# flux/infrastructure/base/controllers/opencost/helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: opencost
  namespace: opencost
spec:
  interval: 10m
  chart:
    spec:
      chart: opencost
      version: "1.x"
      sourceRef:
        kind: HelmRepository
        name: opencost
        namespace: flux-system
  values:
    opencost:
      exporter:
        defaultClusterId: "inferadb-production"
      prometheus:
        internal:
          serviceName: prometheus-operated
          namespaceName: monitoring
      ui:
        enabled: true
        ingress:
          enabled: true
          hosts:
            - host: opencost.internal.inferadb.com
              paths: ["/"]
---
# Alert on namespace cost anomalies
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-alerts
  namespace: monitoring
spec:
  groups:
    - name: cost-alerts
      rules:
        - alert: NamespaceCostSpike
          expr: |
            sum(rate(container_cpu_usage_seconds_total{namespace="inferadb"}[1h]))
            /
            avg_over_time(sum(rate(container_cpu_usage_seconds_total{namespace="inferadb"}[1h]))[7d:1h])
            > 1.5
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "Namespace {{ $labels.namespace }} CPU usage 50% higher than weekly average"
            description: "Review for autoscaling events or performance regressions"
```

### Resource Quotas

```yaml
# flux/infrastructure/production/resource-quotas.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: inferadb-quota
  namespace: inferadb
spec:
  hard:
    requests.cpu: "100"
    requests.memory: "200Gi"
    limits.cpu: "200"
    limits.memory: "400Gi"
    pods: "100"
    services: "20"
    persistentvolumeclaims: "50"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: inferadb-limits
  namespace: inferadb
spec:
  limits:
    - default:
        cpu: "2"
        memory: "2Gi"
      defaultRequest:
        cpu: "500m"
        memory: "512Mi"
      max:
        cpu: "8"
        memory: "16Gi"
      min:
        cpu: "100m"
        memory: "128Mi"
      type: Container
```

---

## 16. Development Environment Specifics

### Local Talos Cluster

```bash
#!/bin/bash
# scripts/dev-up.sh

set -euo pipefail

CLUSTER_NAME="inferadb-dev"

echo "Creating local Talos cluster..."

# Create cluster using talosctl (Docker provisioner)
# Note: Machine config patches are applied via --config-patch-control-plane
# and --config-patch-worker flags, NOT via separate patch files
talosctl cluster create \
  --name ${CLUSTER_NAME} \
  --workers 1 \
  --controlplanes 1 \
  --provisioner docker \
  --kubernetes-version 1.30.0 \
  --config-patch-control-plane @- <<EOF
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: true
  network:
    interfaces:
      - interface: eth0
        dhcp: true
cluster:
  network:
    cni:
      name: none  # We'll install Cilium
EOF

# Get kubeconfig
talosctl kubeconfig --nodes 127.0.0.1 -f ~/.kube/inferadb-dev
export KUBECONFIG=~/.kube/inferadb-dev

# Install Cilium (required before any workloads)
cilium install --helm-set ipam.mode=kubernetes
cilium status --wait

# Bootstrap Flux (simplified for dev - no GitHub, use local path)
kubectl apply -f flux/clusters/dev-local/flux-system/gotk-components.yaml
kubectl apply -f flux/clusters/dev-local/flux-system/gotk-sync.yaml

echo "Development environment ready!"
echo ""
echo "Kubeconfig: export KUBECONFIG=~/.kube/inferadb-dev"
echo "Dashboard: kubectl port-forward -n inferadb svc/inferadb-dashboard 3000:3000"
echo "Engine API: kubectl port-forward -n inferadb svc/inferadb-engine 8080:8080"
```

---

## 17. Runbooks Outline

### Required Runbooks

| Runbook                                                              | Priority | Status         |
| -------------------------------------------------------------------- | -------- | -------------- |
| [FDB Cluster Recovery](runbooks/fdb-cluster-recovery.md)             | Critical | To Create      |
| [Node Replacement](runbooks/node-replacement.md)                     | High     | To Create      |
| [Certificate Rotation](runbooks/certificate-rotation.md)             | High     | To Create      |
| [Partial Region Degradation](runbooks/partial-region-degradation.md) | Critical | To Create      |
| [Full Region Failover](runbooks/full-region-failover.md)             | Critical | To Create      |
| [Secret Rotation](runbooks/secret-rotation.md)                       | High     | To Create      |
| [FDB Upgrade](runbooks/fdb-upgrade.md)                               | High     | Outlined Above |
| [Break-Glass Procedures](runbooks/break-glass-procedures.md)         | Critical | Outlined Above |
| [Talos Upgrade](runbooks/talos-upgrade.md)                           | High     | Outlined Below |

### Talos Linux Upgrade Procedure

```markdown
# runbooks/talos-upgrade.md

## Overview

Talos Linux upgrades require orchestrated node-by-node upgrades using `talosctl`. Unlike
application updates, Talos upgrades cannot be managed by Flux—they require direct API calls.

## Pre-Upgrade Checklist

- [ ] Review Talos release notes for breaking changes
- [ ] Verify current cluster health: `talosctl health --nodes <control-plane-ip>`
- [ ] Verify all workloads are running: `kubectl get pods -A | grep -v Running`
- [ ] Take FDB backup before starting: `fdbcli --exec "backup start"`
- [ ] Test upgrade in staging environment first
- [ ] Schedule maintenance window

## Upgrade Steps

### 1. Prepare Upgrade Image

# Check current version

talosctl version --nodes <control-plane-ip>

# Download new Talos image (if using custom images)

talosctl image pull ghcr.io/siderolabs/talos:v1.9.0

### 2. Upgrade Control Plane Nodes (One at a Time)

# Upgrade first control plane node

talosctl upgrade --nodes cp1.inferadb.io \
 --image ghcr.io/siderolabs/talos:v1.9.0 \
 --preserve

# Wait for node to rejoin cluster

talosctl health --nodes cp1.inferadb.io --wait-timeout 10m

# Verify etcd health

talosctl etcd members --nodes cp1.inferadb.io

# Repeat for remaining control plane nodes

# IMPORTANT: Wait for each node to be healthy before proceeding

### 3. Upgrade Worker Nodes

# Cordon node to prevent new pods

kubectl cordon worker1.inferadb.io

# Drain workloads (respecting PDBs)

kubectl drain worker1.inferadb.io --ignore-daemonsets --delete-emptydir-data

# Upgrade worker

talosctl upgrade --nodes worker1.inferadb.io \
 --image ghcr.io/siderolabs/talos:v1.9.0 \
 --preserve

# Wait for node to rejoin

talosctl health --nodes worker1.inferadb.io --wait-timeout 10m

# Uncordon node

kubectl uncordon worker1.inferadb.io

# Verify pods are scheduled

kubectl get pods -A -o wide | grep worker1

# Repeat for remaining workers

### 4. Post-Upgrade Verification

# Verify all nodes running new version

talosctl version --nodes <all-node-ips>

# Verify cluster health

talosctl health --nodes <control-plane-ip>

# Verify Kubernetes API

kubectl get nodes -o wide

# Verify all pods healthy

kubectl get pods -A | grep -v Running

# Run smoke tests

./scripts/smoke-test.sh

## Rollback Procedure

Talos does not support in-place downgrades. If upgrade fails:

1. **For single node failure**: Re-image node with previous version
   talosctl reset --nodes <failed-node> --graceful=false
   talosctl apply-config --nodes <failed-node> --file <previous-config>

2. **For cluster-wide failure**: Restore from backup
   - Provision new cluster with previous Talos version
   - Restore FDB from backup
   - Update DNS to point to new cluster

## Automation Script

#!/bin/bash

# scripts/talos-upgrade.sh

set -euo pipefail

NEW_VERSION=${1:-v1.9.0}
CONTROL_PLANE_NODES="cp1.inferadb.io cp2.inferadb.io cp3.inferadb.io"
WORKER_NODES="worker1.inferadb.io worker2.inferadb.io worker3.inferadb.io"

echo "Upgrading Talos to ${NEW_VERSION}"

# Upgrade control plane

for node in $CONTROL_PLANE_NODES; do
  echo "Upgrading control plane: ${node}"
  talosctl upgrade --nodes ${node} \
    --image ghcr.io/siderolabs/talos:${NEW_VERSION} \
 --preserve
talosctl health --nodes ${node} --wait-timeout 10m
sleep 30
done

# Upgrade workers

for node in $WORKER_NODES; do
  echo "Upgrading worker: ${node}"
  kubectl cordon ${node}
  kubectl drain ${node} --ignore-daemonsets --delete-emptydir-data --timeout=5m
  talosctl upgrade --nodes ${node} \
    --image ghcr.io/siderolabs/talos:${NEW_VERSION} \
 --preserve
talosctl health --nodes ${node} --wait-timeout 10m
kubectl uncordon ${node}
sleep 30
done

echo "Upgrade complete. Verify with: talosctl version --nodes <any-node>"
```

### Runbook Template

```markdown
# [Runbook Name]

## Overview

Brief description of the scenario this runbook addresses.

## Symptoms

- Symptom 1
- Symptom 2
- Relevant alerts that trigger this runbook

## Prerequisites

- Required access levels
- Required tools
- Required knowledge

## Procedure

### Step 1: Assess the Situation

# Commands to understand current state

### Step 2: [Action]

# Commands to execute

## Verification

How to confirm the issue is resolved.

## Rollback

Steps to undo if the procedure fails.

## Post-Incident

- [ ] Create incident report
- [ ] Schedule post-mortem
- [ ] Update runbook if needed
```

---

## 18. Risks and Tradeoffs

### Identified Risks

| Risk                                    | Impact | Likelihood | Mitigation                                                                 |
| --------------------------------------- | ------ | ---------- | -------------------------------------------------------------------------- |
| **Talos learning curve**                | Medium | High       | Comprehensive documentation, phased rollout starting with dev              |
| **Flux complexity for multi-cluster**   | Medium | Medium     | Start with single cluster per environment, add regions incrementally       |
| **FoundationDB operational complexity** | High   | Medium     | FDB Operator + detailed runbooks + chaos testing                           |
| **Tailscale single point of failure**   | Medium | Low        | Tailscale HA deployment, fallback to direct peering if needed              |
| **Provider-specific edge cases**        | Medium | Medium     | Extensive testing per provider before production use                       |
| **Secret rotation across regions**      | Medium | Low        | External Secrets Operator with automatic rotation + break-glass procedures |
| **FDB cross-region latency**            | High   | High       | Use three_data_hall within region + async DR (not synchronous)             |
| **Supply chain compromise**             | High   | Low        | Image signing + registry restrictions + vulnerability scanning             |

### Tradeoffs Made

| Decision                      | Tradeoff                                     | Rationale                                                         |
| ----------------------------- | -------------------------------------------- | ----------------------------------------------------------------- |
| **Talos over standard Linux** | Less flexibility, steeper learning curve     | Immutability and security outweigh flexibility needs              |
| **Flux over ArgoCD**          | Weaker UI, CLI-focused                       | Multi-cluster native support more important than UI               |
| **Kustomize over Helm-only**  | More files, complexity                       | Environment-specific patches more maintainable                    |
| **Tailscale over native VPN** | Dependency on external service               | Significantly simpler setup, automatic key rotation               |
| **Regional FDB + async DR**   | Potential 1-5s data loss on regional failure | Required due to NYC1-SFO1 latency exceeding FDB sync requirements |
| **Cilium over default CNI**   | Operator complexity                          | Required for NetworkPolicies + mTLS                               |

---

## 19. Implementation Phases

### Phase 1: Foundation ✅

- [x] Create directory structure
- [x] Implement Terraform modules (talos-cluster, provider abstractions)
- [x] Create base Flux configurations
- [x] Implement Cilium CNI configuration
- [x] Set up supply chain security (Cosign, Trivy, Kyverno)
- [x] Document dev-up.sh workflow
- [ ] Test local development environment (requires Talos/Docker runtime)

### Phase 2: Staging NYC1

- [ ] Provision staging infrastructure on primary provider
- [ ] Bootstrap secrets infrastructure
- [ ] Deploy FDB operator and cluster
- [ ] Configure FDB backups
- [ ] Deploy engine, control, dashboard
- [ ] Configure observability stack (Prometheus, Loki, Tempo)
- [ ] Implement network policies
- [ ] Validate autoscaling behavior

### Phase 3: Staging Multi-Region

- [ ] Add SFO1 staging cluster
- [ ] Configure Tailscale mesh
- [ ] Implement FDB async DR replication
- [ ] Configure health-check based DNS failover
- [ ] Test cross-region failover
- [ ] Run chaos engineering tests
- [ ] Load testing with k6

### Phase 4: Production

- [ ] Provision production NYC1
- [ ] Provision production SFO1
- [ ] Configure production monitoring/alerting
- [ ] Implement DR procedures
- [ ] Security audit
- [ ] Implement SLOs and error budgets
- [ ] Configure on-call routing

### Phase 5: Documentation & Operations

- [ ] Finalize all runbooks
- [ ] Train operations team
- [ ] Create region addition playbook
- [ ] Create provider addition playbook
- [ ] Document cost optimization strategies
- [ ] Complete ADRs for all major decisions

---

## 20. Next Steps

1. ~~**Review and approve this plan**~~ ✅
2. ~~**Create initial directory structure** in `deploy/`~~ ✅
3. ~~**Implement Terraform modules** starting with `talos-cluster`~~ ✅
4. **Set up CI/CD pipeline** for image signing and scanning
5. ~~**Create base Flux configurations** with Cilium~~ ✅
6. **Test local development workflow** end-to-end
7. **Begin Phase 2: Staging NYC1** - provision infrastructure and deploy FDB

---

## Appendix A: File Manifest

Files to be created in implementation phase:

```text
deploy/
├── README.md
├── terraform/
│   ├── modules/
│   │   ├── talos-cluster/{main,variables,outputs,versions}.tf
│   │   ├── provider-aws/{main,variables,outputs}.tf
│   │   ├── provider-gcp/{main,variables,outputs}.tf
│   │   ├── provider-digitalocean/{main,variables,outputs}.tf
│   │   ├── tailscale-subnet-router/{main,variables,outputs}.tf
│   │   ├── fdb-backup/{main,variables,outputs}.tf
│   │   └── dns/{main,variables,outputs}.tf
│   ├── environments/
│   │   ├── dev/{main,terraform.tfvars,backend}.tf
│   │   ├── staging/{main,terraform.tfvars,backend}.tf
│   │   └── production/{main,terraform.tfvars,backend}.tf
│   └── regions/
│       ├── nyc1/{aws,digitalocean}/main.tf
│       ├── sfo1/{aws,gcp}/main.tf
│       └── _template/main.tf
├── flux/
│   ├── clusters/{dev-local,staging-nyc1,staging-sfo1,prod-nyc1,prod-sfo1}/
│   ├── infrastructure/{base,dev,staging,production}/
│   ├── apps/{base,dev,staging,production}/
│   └── notifications/
├── talos/
│   ├── controlplane.yaml
│   ├── worker.yaml
│   ├── talconfig.yaml
│   └── patches/{common,dev,staging,production}/
├── policies/
│   ├── kyverno/
│   └── network-policies/
├── scripts/
│   ├── dev-up.sh, dev-down.sh
│   ├── bootstrap-cluster.sh, bootstrap-secrets.sh
│   ├── rotate-secrets.sh, disaster-recovery.sh
│   ├── fdb-backup.sh, fdb-restore.sh
│   └── chaos/
├── runbooks/
│   ├── fdb-cluster-recovery.md
│   ├── node-replacement.md
│   ├── certificate-rotation.md
│   ├── partial-region-degradation.md
│   ├── full-region-failover.md
│   ├── secret-rotation.md
│   ├── fdb-upgrade.md
│   └── break-glass-procedures.md
├── alerts/
│   ├── prometheusrules/
│   └── alertmanager/
├── slos/
├── load-tests/k6/
└── docs/
    └── architecture-decisions/
```

---

## Appendix B: Reference Links

- [Talos Linux Documentation](https://www.talos.dev/docs/)
- [Flux CD Documentation](https://fluxcd.io/docs/)
- [FoundationDB Kubernetes Operator](https://github.com/FoundationDB/fdb-kubernetes-operator)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1185/kubernetes/)
- [Terraform Talos Provider](https://registry.terraform.io/providers/siderolabs/talos/)
- [Cilium Documentation](https://docs.cilium.io/)
- [External Secrets Operator](https://external-secrets.io/)
- [Kyverno Policy Engine](https://kyverno.io/)
- [Sigstore/Cosign](https://docs.sigstore.dev/)
- [k6 Load Testing](https://k6.io/docs/)
