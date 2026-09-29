#!/usr/bin/env bash
# Pre-flight for the burst-deploy. Run BEFORE starting the 60-minute timer
# and BEFORE starting OBS. Catches the failure classes from ADR-0006/0007/0008
# (IAM gaps, repo-vs-live policy drift) while they are still free to fix.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BURST_PROFILE="${AWS_PROFILE:-atlas-network-burst}"
ADMIN_PROFILE="${ADMIN_PROFILE:-default}"
IAM_USER="atlas-network-burst-deploy"
POLICY_FILE="iam/atlas-network-burst-deploy-policy.json"
BUDGET_NAME="atlas-portfolio-burst-deploy"
fail=0

ok()  { echo "ok:   $*"; }
bad() { echo "FAIL: $*" >&2; fail=1; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# 1. Identity — must be the scoped user, never admin
identity="$(AWS_PROFILE="$BURST_PROFILE" aws sts get-caller-identity --output json)"
arn="$(jq -r .Arn <<<"$identity")"
acct="$(jq -r .Account <<<"$identity")"
if [[ "$arn" == *":user/${IAM_USER}" ]]; then ok "running as ${IAM_USER}"; else bad "wrong identity: ${arn}"; fi

# 2. tfvars present, and no leftover state from a previous run
for env in hub spoke-dev spoke-prod core; do
  dir="terraform/environments/${env}"
  [[ -f "${dir}/terraform.tfvars" ]] && ok "${env}: terraform.tfvars present" || bad "${env}: terraform.tfvars missing"
  if [[ -f "${dir}/terraform.tfstate" ]]; then
    n="$(jq '.resources | length' "${dir}/terraform.tfstate")"
    [[ "$n" == "0" ]] && ok "${env}: state empty" || bad "${env}: state has ${n} resources — previous run not destroyed"
  fi
done

# 3. Repo policy == live policy (ADR-0008 root cause)
policy_arn="$(aws iam list-attached-user-policies --user-name "$IAM_USER" \
  --profile "$ADMIN_PROFILE" --query 'AttachedPolicies[0].PolicyArn' --output text)"
version="$(aws iam get-policy --policy-arn "$policy_arn" --profile "$ADMIN_PROFILE" \
  --query 'Policy.DefaultVersionId' --output text)"
live="$(aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$version" \
  --profile "$ADMIN_PROFILE" --query 'PolicyVersion.Document' --output json)"
repo="$(sed "s/__ACCOUNT_ID__/${acct}/g" "$POLICY_FILE")"
if diff <(jq -S . <<<"$repo") <(jq -S . <<<"$live") >/dev/null; then
  ok "repo IAM policy matches live default version"
else
  bad "repo IAM policy DIFFERS from live — push it (see ADR-0008)"
fi

# 4. Simulate every action the runbook and code need
required=(
  ec2:CreateTransitGateway ec2:CreateTransitGatewayVpcAttachment
  ec2:CreateRoute ec2:DeleteRoute
  ec2:SearchTransitGatewayRoutes ec2:DescribeTransitGatewayRouteTables
  ec2:DescribeTransitGatewayAttachments
  ec2:CreateNetworkInsightsPath ec2:StartNetworkInsightsAnalysis
  ec2:DescribeNetworkInsightsAnalyses ec2:DeleteNetworkInsightsPath
  ec2:DescribeNatGateways ec2:DescribeVpcEndpoints ec2:DescribeAddresses
  tiros:CreateQuery tiros:GetQueryAnswer tiros:GetQueryExplanations
)
denied="$(aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::${acct}:user/${IAM_USER}" \
  --action-names "${required[@]}" \
  --context-entries "ContextKeyName=aws:RequestedRegion,ContextKeyValues=us-east-1,ContextKeyType=string" \
  --profile "$ADMIN_PROFILE" \
  --query "EvaluationResults[?EvalDecision!='allowed'].EvalActionName" --output text)"
if [[ -z "$denied" || "$denied" == "None" ]]; then ok "all required actions allowed"; else bad "denied actions: ${denied}"; fi

# 5. Budget healthy (account ID is never echoed — safe near a screen recording)
health="$(aws budgets describe-budgets --account-id "$acct" --profile "$ADMIN_PROFILE" \
  --query "Budgets[?BudgetName=='${BUDGET_NAME}'].HealthStatus.Status | [0]" --output text)"
[[ "$health" == "HEALTHY" ]] && ok "budget HEALTHY" || bad "budget status: ${health}"

# 6. Same checks as CI
./scripts/tf-check.sh >/dev/null && ok "tf-check.sh passes" || bad "tf-check.sh failed"

if [[ "$fail" -ne 0 ]]; then
  echo "PRE-FLIGHT FAILED — do not start the timer." >&2
  exit 1
fi
echo "PRE-FLIGHT PASSED — start OBS + timer, then run scripts/burst-apply.sh"