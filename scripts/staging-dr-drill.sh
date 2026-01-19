#!/bin/bash
# scripts/staging-dr-drill.sh
# Monthly DR drill script for staging environment
# Spins up temporary second region, tests failover, then tears down
# Run monthly to validate DR procedures without maintaining always-on second region

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform/environments/staging"
DRILL_WORKSPACE="sfo1-drill"
DRILL_STARTED=false
DRILL_LOG_DIR="${REPO_ROOT}/dr-drill-results"

# Cleanup function - ensures temporary infra is destroyed on any exit
cleanup() {
  local exit_code=$?

  if [[ "${DRILL_STARTED}" == "true" ]]; then
    echo ""
    echo "=== Cleaning up temporary DR infrastructure ==="

    cd "${TERRAFORM_DIR}"

    if terraform workspace list | grep -q "${DRILL_WORKSPACE}"; then
      echo "Switching to drill workspace..."
      terraform workspace select "${DRILL_WORKSPACE}" 2>/dev/null || true

      echo "Destroying infrastructure..."
      terraform destroy -var="region=sfo1" -auto-approve || \
        echo "Warning: destroy failed, manual cleanup may be required"

      echo "Deleting workspace..."
      terraform workspace select default
      terraform workspace delete "${DRILL_WORKSPACE}" 2>/dev/null || true
    fi
  fi

  if [[ ${exit_code} -ne 0 ]]; then
    echo ""
    echo "=== DR Drill FAILED (exit code: ${exit_code}) ==="
    echo "Check logs in: ${DRILL_LOG_DIR}"
  fi

  exit "${exit_code}"
}

# Set up trap for cleanup on exit, error, interrupt, or termination
trap cleanup EXIT ERR INT TERM

# Start of drill
echo "=== Staging DR Drill Started ==="
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

# Create log directory
mkdir -p "${DRILL_LOG_DIR}"
DRILL_LOG_FILE="${DRILL_LOG_DIR}/$(date +%Y-%m-%d)-drill.log"

# Log function
log() {
  local message="$1"
  echo "${message}"
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") ${message}" >> "${DRILL_LOG_FILE}"
}

log "=== Phase 1: Spin up temporary SFO1 staging cluster ==="

cd "${TERRAFORM_DIR}"

log "Creating or selecting Terraform workspace: ${DRILL_WORKSPACE}"
terraform workspace select "${DRILL_WORKSPACE}" 2>/dev/null || terraform workspace new "${DRILL_WORKSPACE}"

DRILL_STARTED=true

log "Applying Terraform configuration for SFO1 region..."
terraform apply -var="region=sfo1" -auto-approve | tee -a "${DRILL_LOG_FILE}"

log "Terraform apply complete."
echo ""

# Phase 2: Bootstrap temporary cluster
log "=== Phase 2: Bootstrap temporary SFO1 cluster ==="

log "Running bootstrap-cluster.sh for staging-sfo1..."
"${SCRIPT_DIR}/bootstrap-cluster.sh" staging sfo1 aws | tee -a "${DRILL_LOG_FILE}"

log "Cluster bootstrap complete."
echo ""

# Phase 3: Configure Ledger replication
log "=== Phase 3: Configure Ledger replication ==="

LEDGER_DR_MANIFEST="${REPO_ROOT}/flux/apps/staging/ledger/dr-replica.yaml"

if [ -f "${LEDGER_DR_MANIFEST}" ]; then
  log "Applying Ledger DR replica configuration..."
  kubectl --context staging-sfo1 apply -f "${LEDGER_DR_MANIFEST}" | tee -a "${DRILL_LOG_FILE}"

  log "Waiting for Ledger DR replica to be ready..."
  sleep 30

  log "Ledger DR configuration complete."
else
  log "Warning: Ledger DR manifest not found at: ${LEDGER_DR_MANIFEST}"
  log "Skipping Ledger async replication configuration."
fi

echo ""

# Phase 4: Run DR validation tests
log "=== Phase 4: Run DR validation tests ==="

DR_VALIDATION_SCRIPT="${SCRIPT_DIR}/dr-validation-tests.sh"

if [ -f "${DR_VALIDATION_SCRIPT}" ]; then
  log "Running DR validation tests..."
  "${DR_VALIDATION_SCRIPT}" | tee -a "${DRILL_LOG_FILE}"
  log "DR validation tests complete."
else
  log "Warning: DR validation script not found at: ${DR_VALIDATION_SCRIPT}"
  log "Skipping validation tests."
  log "To create validation tests, implement: ${DR_VALIDATION_SCRIPT}"
fi

echo ""

# Phase 5: Record results
log "=== Phase 5: Recording results ==="

cat >> "${DRILL_LOG_FILE}" <<EOFREPORT

=== DR Drill Summary ===

Drill Date: $(date -u +"%Y-%m-%d")
Drill Time: $(date -u +"%H:%M:%S UTC")

Infrastructure:
  - Primary Region: NYC1
  - DR Region: SFO1 (temporary)
  - Terraform Workspace: ${DRILL_WORKSPACE}

Results:
  - Infrastructure provisioning: SUCCESS
  - Cluster bootstrap: SUCCESS
  - Ledger replication: $([ -f "${LEDGER_DR_MANIFEST}" ] && echo "SUCCESS" || echo "SKIPPED")
  - Validation tests: $([ -f "${DR_VALIDATION_SCRIPT}" ] && echo "SUCCESS" || echo "SKIPPED")

Next Steps:
  1. Review this log file
  2. Document any issues encountered
  3. Update runbooks if necessary
  4. Schedule next drill for $(date -u -d "+1 month" +"%Y-%m-%d" 2>/dev/null || date -u -v+1m +"%Y-%m-%d" 2>/dev/null || echo "next month")

=== End of Summary ===
EOFREPORT

log "Results recorded to: ${DRILL_LOG_FILE}"

echo ""
log "=== DR Drill Complete ==="
log "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""
log "Drill log saved to: ${DRILL_LOG_FILE}"
echo ""
log "Cleanup will now proceed (via trap handler)..."

# Exit successfully - cleanup trap will handle infrastructure destruction
exit 0
