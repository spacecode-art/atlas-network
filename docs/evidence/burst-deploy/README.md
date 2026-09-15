# Burst-Deploy Runbook

Operational steps for the one live deployment permitted by ADR-0005.
Read ADR-0005 in full before running this — this document is the *how*,
the ADR is the *why* and the *rules* (scope, 60-minute limit, $5
ceiling, billing safety).

Do not deviate from this order. Do not add resources "since we're
already in there." If something breaks mid-window: destroy immediately,
debug afterward from the (free) logs.

---

## 0. Pre-flight (do this before starting the timer)

- [ ] `AWS_PROFILE=atlas-network-burst aws sts get-caller-identity` —
      confirms you're on the scoped user, not admin
- [ ] `aws budgets describe-budgets --account-id 803347590852 --profile default`
      — confirms the budget is still `HEALTHY`
- [ ] Real `terraform.tfvars` created in all four environment directories
      (copy from `.tfvars.example`, fill in a real `owner` value — these
      are gitignored, create them fresh, don't commit them)
- [ ] `./scripts/tf-check.sh` passes clean on `main` (CI green) —
      don't burst-deploy against unvalidated Terraform
- [ ] `mkdir -p docs/evidence/burst-deploy/$(date +%Y-%m-%d)` — this run's
      evidence folder, referenced as `$EVIDENCE_DIR` below
- [ ] Screen recording started (per README's Demo Video requirement)
- [ ] **Start the 60-minute timer now, on your phone or a visible clock
      — not a mental estimate.**

```bash
export AWS_PROFILE=atlas-network-burst
export AWS_DEFAULT_REGION=us-east-1
export EVIDENCE_DIR="docs/evidence/burst-deploy/$(date +%Y-%m-%d)"
mkdir -p "$EVIDENCE_DIR"
```

---

## 1. Apply — in this exact order

Leaf environments first (`core` depends on their state), each one's
`apply` output captured to this run's evidence folder.

```bash
for env in hub spoke-dev spoke-prod; do
  echo "=== applying $env ===" | tee -a "$EVIDENCE_DIR/apply-log.txt"
  terraform -chdir="terraform/environments/${env}" apply \
    -var-file="terraform.tfvars" -auto-approve \
    | tee -a "$EVIDENCE_DIR/apply-log.txt"
done

echo "=== applying core ===" | tee -a "$EVIDENCE_DIR/apply-log.txt"
terraform -chdir="terraform/environments/core" apply \
  -var-file="terraform.tfvars" -auto-approve \
  | tee -a "$EVIDENCE_DIR/apply-log.txt"
```

If any `apply` fails: stop, `terraform destroy -var-file="terraform.tfvars" -auto-approve`
on whatever already applied (reverse order — see Step 4), and debug from
the captured log. Do not retry blind inside the live window.

---

## 2. Capture — Transit Gateway route segmentation (the evidence that
matters most)

Reachability Analyzer supports Transit Gateway **attachments** directly
as source/destination — no EC2 instances needed. Look up the three
attachment IDs by tag, then run three paths.

```bash
HUB_ATTACH=$(aws ec2 describe-transit-gateway-attachments \
  --filters "Name=tag:Name,Values=atlas-network-attach-hub" \
  --query "TransitGatewayAttachments[0].TransitGatewayAttachmentId" --output text)

DEV_ATTACH=$(aws ec2 describe-transit-gateway-attachments \
  --filters "Name=tag:Name,Values=atlas-network-attach-dev" \
  --query "TransitGatewayAttachments[0].TransitGatewayAttachmentId" --output text)

PROD_ATTACH=$(aws ec2 describe-transit-gateway-attachments \
  --filters "Name=tag:Name,Values=atlas-network-attach-prod" \
  --query "TransitGatewayAttachments[0].TransitGatewayAttachmentId" --output text)

echo "hub=$HUB_ATTACH dev=$DEV_ATTACH prod=$PROD_ATTACH"
```

Run and capture all three paths — expect the first two **Reachable**,
the third **Not reachable** (that's ADR-0002 proven, not just planned):

```bash
run_path () {
  local name=$1 src=$2 dst=$3
  local path_id analysis_id
  path_id=$(aws ec2 create-network-insights-path \
    --source "$src" --destination "$dst" \
    --query "NetworkInsightsPath.NetworkInsightsPathId" --output text)
  analysis_id=$(aws ec2 start-network-insights-analysis \
    --network-insights-path-id "$path_id" \
    --query "NetworkInsightsAnalysis.NetworkInsightsAnalysisId" --output text)
  sleep 15  # analysis is near-instant but not synchronous
  aws ec2 describe-network-insights-analyses \
    --network-insights-analysis-ids "$analysis_id" \
    > "$EVIDENCE_DIR/reachability-${name}.json"
  echo "=== ${name} ===" && jq '.NetworkInsightsAnalyses[0].NetworkPathFound' "$EVIDENCE_DIR/reachability-${name}.json"
  # cleanup — path/analysis are free but no reason to leave them
  aws ec2 delete-network-insights-path --network-insights-path-id "$path_id" > /dev/null
}

run_path "hub-to-dev"  "$HUB_ATTACH" "$DEV_ATTACH"
run_path "hub-to-prod" "$HUB_ATTACH" "$PROD_ATTACH"
run_path "dev-to-prod" "$DEV_ATTACH" "$PROD_ATTACH"
```

- [ ] `reachability-hub-to-dev.json` → `NetworkPathFound: true`
- [ ] `reachability-hub-to-prod.json` → `NetworkPathFound: true`
- [ ] `reachability-dev-to-prod.json` → `NetworkPathFound: false` — **this
      is the one result that actually matters**, screenshot the console
      view of it too (Network path blocked, showing which route table
      lacks the propagation)

---

## 3. Capture — screenshots (console, while the stack is still live)

Save each into `$EVIDENCE_DIR/`:

- [ ] `tgw-route-table-hub.png` — hub's TGW route table, showing routes
      learned from *both* spokes
- [ ] `tgw-route-table-dev.png` — dev spoke's TGW route table, showing
      it only ever learned the hub's route (never prod's)
- [ ] `tgw-route-table-prod.png` — same, for prod
- [ ] `privatelink-endpoint-status.png` — the S3 Interface Endpoint,
      status `available`, showing its DNS entries
- [ ] `nat-gateways.png` — all three NAT Gateways (1 dev + 2 prod),
      status `available`

---

## 4. Destroy — reverse order, before the 60 minutes are up

```bash
terraform -chdir="terraform/environments/core" destroy \
  -var-file="terraform.tfvars" -auto-approve \
  | tee "$EVIDENCE_DIR/destroy-log.txt"

for env in spoke-prod spoke-dev hub; do
  echo "=== destroying $env ===" | tee -a "$EVIDENCE_DIR/destroy-log.txt"
  terraform -chdir="terraform/environments/${env}" destroy \
    -var-file="terraform.tfvars" -auto-approve \
    | tee -a "$EVIDENCE_DIR/destroy-log.txt"
done
```

- [ ] Every `destroy` reports `Destroy complete! Resources: N destroyed.`
      — captured in `destroy-log.txt`, timestamped

---

## 5. Post-window verification (next day, not optional)

- [ ] AWS Console → VPC → confirm no VPCs, TGWs, NAT Gateways, or
      Elastic IPs remain tagged `atlas-network*`
- [ ] Cost Explorer → filter to the deploy window → screenshot →
      `$EVIDENCE_DIR/cost-explorer.png` (feeds `atlas-finops` as a real
      data point)
- [ ] AWS Billing Console → Credits balance → confirm it dropped by
      roughly the modeled amount (~$0.25), not more
- [ ] `aws budgets describe-budgets --account-id 803347590852 --profile default`
      → `HealthStatus` still `HEALTHY`

---

## 6. After this repo — commit the evidence

```bash
git add docs/evidence/burst-deploy/
git commit -m "evidence: burst-deploy run $(date +%Y-%m-%d)

Reachability Analyzer confirms ADR-0002's route segmentation against
real Transit Gateway: hub<->dev reachable, hub<->prod reachable,
dev<->prod not reachable. Full apply/destroy logs, TGW route table and
PrivateLink endpoint screenshots, Cost Explorer capture included.
Window: <actual duration>, cost: <actual amount from Cost Explorer>."
git push
```

Update `docs/cost-model/burst-deploy-actuals.md` with the real numbers
(time taken, actual cost from Cost Explorer, any deviation from ADR-0005's
modeled $0.25) — separate small commit, not bundled with evidence.