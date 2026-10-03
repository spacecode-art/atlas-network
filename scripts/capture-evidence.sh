#!/usr/bin/env bash
# Captures the evidence that proves ADR-0002 on a real control plane.
# Primary evidence: TGW route table contents (deterministic, asserted).
# Secondary: Reachability Analyzer paths (asserted). RA failure does NOT stop
# teardown — capture what you can, then run destroy-all.sh.
set -euo pipefail

: "${AWS_PROFILE:=atlas-network-burst}"
export AWS_PROFILE AWS_DEFAULT_REGION=us-east-1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EVIDENCE_DIR="${EVIDENCE_DIR:-docs/evidence/burst-deploy/$(date -u +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"
rc=0

outputs="$(terraform -chdir=terraform/environments/core output -json)"
HUB="$(jq -r '.hub_attachment_id.value' <<<"$outputs")"
DEV="$(jq -r '.spoke_attachment_ids.value.dev' <<<"$outputs")"
PROD="$(jq -r '.spoke_attachment_ids.value.prod' <<<"$outputs")"
echo "attachments hub=${HUB} dev=${DEV} prod=${PROD}"

# ---- 1. TGW route tables (primary evidence) --------------------------------
for rt in hub dev prod; do
  rtb="$(aws ec2 describe-transit-gateway-route-tables \
    --filters "Name=tag:Name,Values=atlas-network-rtb-${rt}" "Name=state,Values=available" \
    --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' --output text)"
  aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id "$rtb" \
    --filters "Name=state,Values=active,blackhole" > "${EVIDENCE_DIR}/tgw-routes-${rt}.json"
done

has_route() { jq -e --arg c "$2" '[.Routes[].DestinationCidrBlock] | index($c) != null' \
  "${EVIDENCE_DIR}/tgw-routes-$1.json" >/dev/null; }
expect() { # expect <table> <cidr> <present|absent>
  local present=0; has_route "$1" "$2" && present=1
  if { [[ "$3" == present && $present -eq 1 ]] || [[ "$3" == absent && $present -eq 0 ]]; }; then
    echo "ok:   tgw rtb-$1 ${3} ${2}"
  else
    echo "FAIL: tgw rtb-$1 expected ${2} ${3}" >&2; rc=1
  fi
}
expect hub  10.101.0.0/16 present
expect hub  10.102.0.0/16 present
expect dev  10.100.0.0/16 present
expect dev  10.102.0.0/16 absent
expect prod 10.100.0.0/16 present
expect prod 10.101.0.0/16 absent

# ---- 2. Resource inventory -------------------------------------------------
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" \
  > "${EVIDENCE_DIR}/nat-gateways.json"
aws ec2 describe-vpc-endpoints > "${EVIDENCE_DIR}/vpc-endpoints.json"
aws ec2 describe-transit-gateway-attachments > "${EVIDENCE_DIR}/tgw-attachments.json"

# ---- 3. Reachability Analyzer (secondary evidence) -------------------------
run_path() { # run_path <name> <src> <dst> <expected true|false>
  local name=$1 src=$2 dst=$3 expected=$4 path_id analysis_id status found
  path_id="$(aws ec2 create-network-insights-path --source "$src" --destination "$dst" \
    --protocol tcp --query 'NetworkInsightsPath.NetworkInsightsPathId' --output text)" || return 1
  analysis_id="$(aws ec2 start-network-insights-analysis --network-insights-path-id "$path_id" \
    --query 'NetworkInsightsAnalysis.NetworkInsightsAnalysisId' --output text)"
  for _ in $(seq 1 36); do
    status="$(aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$analysis_id" \
      --query 'NetworkInsightsAnalyses[0].Status' --output text)"
    if [[ "$status" != "running" ]]; then break; fi
    sleep 5
  done
  aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$analysis_id" \
    > "${EVIDENCE_DIR}/reachability-${name}.json"
  found="$(jq -r '.NetworkInsightsAnalyses[0].NetworkPathFound' "${EVIDENCE_DIR}/reachability-${name}.json")"
  # Kept so the console can be screenshotted; destroy-all.sh deletes them.
  echo "$path_id" >> "${EVIDENCE_DIR}/ra-path-ids.txt"
  if [[ "$status" == "succeeded" && "$found" == "$expected" ]]; then
    echo "ok:   RA ${name} NetworkPathFound=${found}"
  else
    echo "FAIL: RA ${name} status=${status} found=${found} expected=${expected}" >&2
    jq -r '.NetworkInsightsAnalyses[0].StatusMessage // empty' "${EVIDENCE_DIR}/reachability-${name}.json" >&2
    return 1
  fi
}
run_path hub-to-dev  "$HUB" "$DEV"  true  || rc=1
run_path hub-to-prod "$HUB" "$PROD" true  || rc=1
run_path dev-to-prod "$DEV" "$PROD" false || rc=1

# ---- 4. Redact the account ID before anything is committed -----------------
"${ROOT}/scripts/redact-evidence.sh" "$EVIDENCE_DIR"

[[ $rc -eq 0 ]] && echo "CAPTURE OK" || echo "CAPTURE HAD FAILURES — still run destroy-all.sh" >&2
exit $rc