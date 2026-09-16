#!/usr/bin/env bash
set -euo pipefail

# Enforces the ADR-0007 destroy order for the atlas-network stack.
# core's remote-state stitching (terraform_remote_state reading hub,
# spoke-dev, spoke-prod) means destroying in apply order instead of
# reverse breaks core's ability to even run terraform destroy — see
# ADR-0007 for the full incident. This script exists so that order is
# enforced in code, not memory, under time pressure.

: "${AWS_PROFILE:=atlas-network-burst}"
EVIDENCE_DIR="docs/evidence/burst-deploy/$(date +%Y-%m-%d)"
mkdir -p "$EVIDENCE_DIR"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ORDER=(core spoke-prod spoke-dev hub)

for env in "${ORDER[@]}"; do
  echo "=== Destroying ${env} (AWS_PROFILE=${AWS_PROFILE}) ==="
  AWS_PROFILE="$AWS_PROFILE" terraform -chdir="terraform/environments/${env}" destroy \
    -var-file="terraform.tfvars" -auto-approve \
    | tee "${EVIDENCE_DIR}/${env}-destroy.txt"
  echo "=== ${env} destroy complete ==="
done

echo ""
echo "=== Verification sweep (ground truth, not just Terraform's log) ==="
aws ec2 describe-vpcs --profile default \
  --filters "Name=tag:Owner,Values=dennisk-atlas-portfolio" \
  --query "Vpcs[].VpcId" --output text | tee "${EVIDENCE_DIR}/final-vpc-check.txt"
aws ec2 describe-transit-gateways --profile default \
  --query "TransitGateways[?State!='deleted']" | tee "${EVIDENCE_DIR}/final-tgw-check.txt"
aws ec2 describe-addresses --profile default \
  --query "Addresses[]" | tee "${EVIDENCE_DIR}/final-eip-check.txt"

echo ""
echo "If all three checks above are empty, the burst-deploy is fully torn down."
echo "If not, STOP — do not re-run this script blind. Investigate per ADR-0005/0007."