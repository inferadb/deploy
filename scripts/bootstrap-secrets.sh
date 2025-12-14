#!/bin/bash
# scripts/bootstrap-secrets.sh
# Secret bootstrapping script for InferaDB
# Generates SOPS age keys and creates bootstrap secrets for External Secrets Operator

set -euo pipefail

# Parse arguments with defaults
ENVIRONMENT="${1:-staging}"
CLUSTER="${2:-nyc1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Bootstrapping Secrets for InferaDB ==="
echo "Environment: ${ENVIRONMENT}"
echo "Cluster:     ${CLUSTER}"
echo ""

# Step 1: Generate SOPS age key (stored securely, never in git)
echo "=== Step 1: SOPS Age Key Generation ==="

SOPS_AGE_KEY_DIR="$HOME/.config/sops/age"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_DIR}/keys.txt"

if [ -f "${SOPS_AGE_KEY_FILE}" ]; then
  echo "SOPS age key already exists at: ${SOPS_AGE_KEY_FILE}"
  echo "Skipping key generation."
else
  echo "Generating new SOPS age key..."
  mkdir -p "${SOPS_AGE_KEY_DIR}"
  age-keygen -o "${SOPS_AGE_KEY_FILE}"
  chmod 600 "${SOPS_AGE_KEY_FILE}"
  echo "SOPS age key generated at: ${SOPS_AGE_KEY_FILE}"
  echo ""
  echo "WARNING: This key is required to decrypt secrets. Back it up securely!"
fi

echo ""

# Step 2: Create bootstrap secret for External Secrets Operator
echo "=== Step 2: External Secrets Operator Bootstrap ==="

echo "Creating bootstrap secret for External Secrets Operator..."
echo "This secret allows ESO to authenticate with the secret provider."
echo ""

# Check if AWS credentials are available
if ! aws configure get aws_access_key_id >/dev/null 2>&1; then
  echo "Error: AWS credentials not found."
  echo "Please configure AWS CLI with: aws configure"
  exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Create the bootstrap secret
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

echo "External Secrets Operator bootstrap secret created."
echo ""

# Step 3: Create SOPS-encrypted secrets for Flux (git-stored)
echo "=== Step 3: SOPS-Encrypted Secrets for Flux ==="

# Extract age public key
AGE_PUBLIC_KEY=$(grep "public key" "${SOPS_AGE_KEY_FILE}" | cut -d: -f2 | tr -d ' ')

if [ -z "${AGE_PUBLIC_KEY}" ]; then
  echo "Error: Could not extract age public key from ${SOPS_AGE_KEY_FILE}"
  exit 1
fi

echo "Age public key: ${AGE_PUBLIC_KEY}"

# Path to encrypted secrets
SECRETS_DEC_FILE="${REPO_ROOT}/flux/clusters/${ENVIRONMENT}-${CLUSTER}/secrets.yaml.dec"
SECRETS_ENC_FILE="${REPO_ROOT}/flux/clusters/${ENVIRONMENT}-${CLUSTER}/secrets.yaml"

# Check if decrypted secrets file exists
if [ ! -f "${SECRETS_DEC_FILE}" ]; then
  echo "Warning: Decrypted secrets file not found at: ${SECRETS_DEC_FILE}"
  echo "Creating example secrets file..."

  mkdir -p "$(dirname "${SECRETS_DEC_FILE}")"

  cat > "${SECRETS_DEC_FILE}" <<'EOFTEMPLATE'
# Example secrets file - replace with actual secrets
# This file should NOT be committed to git
apiVersion: v1
kind: Secret
metadata:
  name: example-secret
  namespace: inferadb
type: Opaque
stringData:
  example-key: "example-value"
EOFTEMPLATE

  echo "Example secrets file created at: ${SECRETS_DEC_FILE}"
  echo "Please edit this file with actual secrets before encrypting."
  echo ""
fi

# Encrypt secrets with SOPS
echo "Encrypting secrets with SOPS..."
sops --encrypt --age "${AGE_PUBLIC_KEY}" "${SECRETS_DEC_FILE}" > "${SECRETS_ENC_FILE}"

echo "Secrets encrypted and saved to: ${SECRETS_ENC_FILE}"
echo ""

# Step 4: Create SOPS secret for Flux decryption
echo "=== Step 4: SOPS Decryption Secret for Flux ==="

# Create namespace if it doesn't exist
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

# Create secret with age private key for Flux to decrypt SOPS-encrypted files
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey="${SOPS_AGE_KEY_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "SOPS decryption secret created in flux-system namespace."
echo ""

echo "=== Bootstrap Complete ==="
echo ""
echo "Summary:"
echo "  1. SOPS age key: ${SOPS_AGE_KEY_FILE} (backup this securely!)"
echo "  2. External Secrets Operator bootstrap secret created"
echo "  3. SOPS-encrypted secrets: ${SECRETS_ENC_FILE}"
echo "  4. Flux decryption secret created in flux-system namespace"
echo ""
echo "External Secrets Operator can now sync remaining secrets from AWS Secrets Manager."
echo "Flux can decrypt SOPS-encrypted files using the age key."
echo ""
echo "IMPORTANT: Add ${SECRETS_DEC_FILE} to .gitignore!"
echo "           Only commit ${SECRETS_ENC_FILE} to git."
echo ""
