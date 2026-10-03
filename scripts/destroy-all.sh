#!/usr/bin/env bash
set -euo pipefail

# Enforces the ADR-0007 destroy order. core's terraform_remote_state reads
# hub/spoke-dev/spoke-prod, so destroying in apply order breaks core.
# Ends with a ground-truth sweep and exits non-zero if ANYTHING is left.

: "${AWS_PROFILE:=atlas-network-burst}"
ADMIN_PROFILE="${ADMIN_PROFILE:-default}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EVIDENCE_DIR="${EVIDENCE_DIR:-docs/evidence/burst-deploy/$(date -u +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"

OWNER="${OWNER:-$(awk -F'"' '/^owner/ {print $2; exit}' terraform/environments/hub/terraform.tfvars)}"
[[ -n "$OWNER" ]] || { echo "could not resolve OWNER (set OWNER=... or fill hub/terraform.tfvars)" >&2; exit 1; }

ORDER=(core spoke-prod spoke-dev hub)
for env in "${ORDER[@]}"; do
  echo "=== Destroying ${env} @ $(date -u +%H:%M:%SZ) (AWS_PROFILE=${AWS_PROFILE}) ==="
  AWS_PROFILE="$AWS_PROFILE" terraform -chdir="terraform/environments/${env}" destroy \
    -var-file="terraform.tfvars" -auto-approve -no-color -input=false \
    | tee "${EVIDENCE_DIR}/${env}-destroy.txt"
  echo "=== ${env} destroy complete ==="
  if [[ -f "${EVIDENCE_DIR}/ra-path-ids.txt" ]]; then
  while read -r p; do
    [[ -n "$p" ]] || continue
    aws ec2 delete-network-insights-path --network-insights-path-id "$p" \
      --profile "$AWS_PROFILE" >/dev/null || true
  done < "${EVIDENCE_DIR}/ra-path-ids.txt"
fi
done

echo ""
echo "=== Verification sweep (ground truth, not Terraform's log) ==="
leftovers=()
sweep() { # sweep <name> <aws args...>
  local name=$1; shift
  local out
  out="$(aws "$@" --profile "$ADMIN_PROFILE" --output text)"
  printf '%s\n' "$out" | tee "${EVIDENCE_DIR}/final-${name}-check.txt"
  if [[ -n "$out" && "$out" != "None" ]]; then leftovers+=("$name"); fi
}

sweep vpc  ec2 describe-vpcs --filters "Name=tag:Owner,Values=${OWNER}" --query "Vpcs[].VpcId"
sweep tgw  ec2 describe-transit-gateways --query "TransitGateways[?State!='deleted'].TransitGatewayId"
sweep eip  ec2 describe-addresses --query "Addresses[].AllocationId"
sweep nat  ec2 describe-nat-gateways --query "NatGateways[?State!='deleted'].NatGatewayId"
sweep vpce ec2 describe-vpc-endpoints --query "VpcEndpoints[?State!='deleted'].VpcEndpointId"
sweep eni  ec2 describe-network-interfaces \
  --filters "Name=interface-type,Values=nat_gateway,vpc_endpoint,transit_gateway" \
  --query "NetworkInterfaces[].NetworkInterfaceId"

echo ""
if [[ ${#leftovers[@]} -eq 0 ]]; then
  echo "CLEAN: burst-deploy fully torn down."
else
  echo "LEFTOVERS: ${leftovers[*]} — STOP. Do not re-run blind. Investigate per ADR-0005/0007." >&2
  exit 1
fi