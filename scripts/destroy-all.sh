#!/usr/bin/env bash
set -euo pipefail

# Enforces the ADR-0007 destroy order. core's terraform_remote_state reads
# hub/spoke-dev/spoke-prod, so destroying in apply order breaks core.
# Order of operations:
#   1. Reachability Analyzer cleanup (analyses must be deleted before paths)
#   2. terraform destroy: core -> spoke-prod -> spoke-dev -> hub
#   3. Ground-truth sweep; exits non-zero if ANYTHING is left.

: "${AWS_PROFILE:=atlas-network-burst}"
ADMIN_PROFILE="${ADMIN_PROFILE:-default}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EVIDENCE_DIR="${EVIDENCE_DIR:-docs/evidence/burst-deploy/$(date -u +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"

OWNER="${OWNER:-$(awk -F'"' '/^owner/ {print $2; exit}' terraform/environments/hub/terraform.tfvars)}"
[[ -n "$OWNER" ]] || { echo "could not resolve OWNER (set OWNER=... or fill hub/terraform.tfvars)" >&2; exit 1; }

CURRENT_STEP="startup"
trap 'echo "DESTROY FAILED during: ${CURRENT_STEP}. Fix the cause and re-run this script; do not abandon the window." >&2' ERR

# ---------------------------------------------------------------------------
# 1. Reachability Analyzer cleanup (AWS rejects deleting a path that still
#    has analyses, so delete analyses first). Failures warn but do not abort:
#    the sweep below is the authority on what is left.
# ---------------------------------------------------------------------------
CURRENT_STEP="reachability analyzer cleanup"
echo "=== Cleaning up Reachability Analyzer analyses and paths ==="
ra_paths="$(aws ec2 describe-network-insights-paths --profile "$AWS_PROFILE" \
  --query 'NetworkInsightsPaths[].NetworkInsightsPathId' --output text)"
if [[ -n "$ra_paths" && "$ra_paths" != "None" ]]; then
  for p in $ra_paths; do
    analyses="$(aws ec2 describe-network-insights-analyses --network-insights-path-id "$p" \
      --profile "$AWS_PROFILE" \
      --query 'NetworkInsightsAnalyses[].NetworkInsightsAnalysisId' --output text)"
    if [[ -n "$analyses" && "$analyses" != "None" ]]; then
      for a in $analyses; do
        aws ec2 delete-network-insights-analysis --network-insights-analysis-id "$a" \
          --profile "$AWS_PROFILE" >/dev/null || echo "WARN: could not delete analysis $a" >&2
      done
    fi
    aws ec2 delete-network-insights-path --network-insights-path-id "$p" \
      --profile "$AWS_PROFILE" >/dev/null || echo "WARN: could not delete path $p" >&2
    echo "removed path $p"
  done
else
  echo "no Reachability Analyzer paths found"
fi

# ---------------------------------------------------------------------------
# 2. Terraform destroy in reverse dependency order.
# ---------------------------------------------------------------------------
ORDER=(core spoke-prod spoke-dev hub)
for env in "${ORDER[@]}"; do
  CURRENT_STEP="terraform destroy (${env})"
  echo "=== Destroying ${env} @ $(date -u +%H:%M:%SZ) (AWS_PROFILE=${AWS_PROFILE}) ==="
  AWS_PROFILE="$AWS_PROFILE" terraform -chdir="terraform/environments/${env}" destroy \
    -var-file="terraform.tfvars" -auto-approve -no-color -input=false \
    | tee "${EVIDENCE_DIR}/${env}-destroy.txt"
  echo "=== ${env} destroy complete ==="
done

# ---------------------------------------------------------------------------
# 3. Verification sweep: ground truth from the AWS API, not Terraform's log.
# ---------------------------------------------------------------------------
CURRENT_STEP="verification sweep"
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
sweep ra   ec2 describe-network-insights-paths --query "NetworkInsightsPaths[].NetworkInsightsPathId"

echo ""
if [[ ${#leftovers[@]} -eq 0 ]]; then
  echo "CLEAN: burst-deploy fully torn down."
else
  echo "LEFTOVERS: ${leftovers[*]}. STOP. Do not re-run blind. Investigate per ADR-0005/0007." >&2
  exit 1
fi