# Burst-Deploy Runbook

The *how*. ADR-0005 is the *why* and the rules (60 min, $5 ceiling, billing
safety); ADR-0009 explains the scripts. Do not add resources mid-window.
If anything breaks: destroy first, debug from logs afterward.

## 0. Before (outside the window)

1. Push the current IAM policy live if it changed (ADR-0008, ADR-0009).
2. Copy each `terraform.tfvars.example` → `terraform.tfvars`, set `owner`.
3. Confirm no leftovers from earlier runs (`preflight.sh` checks state).
4. Rehearse the OBS scenes once with no AWS involved.
5. Pre-open console tabs in us-east-1: TGW route tables, VPC endpoints, NAT gateways.
   Crop or blur the account ID (top-right).

```bash
./scripts/preflight.sh      # must print PRE-FLIGHT PASSED
```

## 1. Start (t = 0)

Start OBS recording and a visible UTC clock. Then:

```bash
export AWS_PROFILE=atlas-network-burst
date -u
./scripts/burst-apply.sh    # hub → spoke-dev → spoke-prod → core (~12 min)
```

If it fails: `./scripts/destroy-all.sh` immediately.

## 2. Capture

```bash
./scripts/capture-evidence.sh
```

Asserts: hub RT has both spoke CIDRs; dev RT has only the hub CIDR (no
`10.102.0.0/16`); prod RT has only the hub CIDR; RA hub→dev and hub→prod
reachable, dev→prod not reachable. Non-zero exit = a mismatch or RA error;
keep going to teardown either way.

If RA rejects attachment-to-attachment paths, the TGW route table JSON is
your primary evidence (ADR-0009). Record the RA limitation in the actuals doc.

## 3. Screenshots (console, stack still live)

Save into the evidence directory:
- `tgw-route-table-hub.png`, `tgw-route-table-dev.png`, `tgw-route-table-prod.png`
- `privatelink-endpoint-status.png` (status `available`, DNS entries visible)
- `nat-gateways.png` (1 dev + 2 prod, `available`)
- `reachability-dev-to-prod.png` (Not reachable, showing why)

## 4. Destroy (before t = 60 min)

```bash
./scripts/destroy-all.sh    # reverse order + sweep; exits non-zero on leftovers
```

Expect the last line `CLEAN: burst-deploy fully torn down.` Leave OBS
recording until you see it. Then stop recording.

## 5. Redact and commit

```bash
./scripts/redact-evidence.sh "docs/evidence/burst-deploy/$(date -u +%Y-%m-%d)"
git add docs/evidence/burst-deploy/
git commit -m "evidence: final burst-deploy $(date -u +%Y-%m-%d)"
```

Host the video externally (YouTube unlisted / GitHub Release) and link it
from the README's Demo Video section.

## 6. Next day (not optional)

- [ ] Console: no VPCs, TGWs, NAT gateways, EIPs, endpoints or ENIs tagged `atlas-network*`
- [ ] Cost Explorer for the window → `cost-explorer.png`
- [ ] Billing → Credits balance dropped by roughly ~$0.61, not more
- [ ] Budget still `HEALTHY`
- [ ] Fill in `docs/cost-model/burst-deploy-actuals.md` (separate commit)