# Threat Model — atlas-network (STRIDE)

Scope: hub-and-spoke Transit Gateway, one PrivateLink Interface Endpoint (S3),
NAT egress, the burst-deploy IAM user, and Terraform state. Out of scope:
workloads inside the VPCs (none are deployed).

## Assets

- Segmentation between `spoke-dev` and `spoke-prod` (ADR-0002)
- Private reachability of the endpoint service (ADR-0003)
- The burst-deploy IAM credentials
- Terraform state (contains resource IDs; local, gitignored)

## Trust boundaries

Internet ↔ NAT gateways · spoke ↔ hub via TGW · consumer VPC ↔ endpoint ENI ·
operator workstation ↔ AWS API

## Threats

| # | Threat | STRIDE | Mitigation | Residual / evidence |
|---|---|---|---|---|
| 1 | Someone adds a TGW attachment and it inherits permissive default routing | Elevation of privilege | Default association/propagation disabled on the TGW; new attachments fail closed | Terratest `TestTransitGatewayModulePlanEnforcesSpokeSegmentation` |
| 2 | Propagation misconfigured so dev learns prod's CIDR | Information disclosure / Tampering | Each spoke RT propagates from the hub attachment only; asserted against real route tables | `tgw-routes-dev.json` must not contain `10.102.0.0/16` |
| 3 | VPC route added that bypasses intended paths (e.g. dev→prod) | Tampering | Only hub CIDR routes exist in spoke RTs (`core/main.tf`) | Reviewed in PR; plan diff |
| 4 | Endpoint reachable from CIDRs beyond the consumer spoke | Information disclosure | SG ingress limited to spoke CIDR on 443; module rejects `0.0.0.0/0`; no egress rules | Terratest asserts scoped ingress |
| 5 | Endpoint used for exfiltration to arbitrary buckets | Information disclosure | Read-only endpoint policy | Policy is broad on `Resource: "*"` — accepted for demo, restrict by bucket ARN in a real deployment |
| 6 | NAT gateway AZ failure removes egress | Denial of service | Prod: per-AZ NAT; Dev: single NAT accepted (ADR-0004) | Dev outage accepted for cost |
| 7 | CIDR overlap when attached to a real multi-account TGW | Denial of service | Non-overlapping ranges (ADR-0001) | Revisit if attached to foundation ranges |
| 8 | Burst-deploy credentials leaked or over-privileged | Spoofing / Elevation | Dedicated IAM user, no console, region-locked deny, no IAM writes except one SLR; credentials only in a named CLI profile | Policy drift caught by `preflight.sh` |
| 9 | Forgotten billable resources after the window | Denial of service (financial) | `destroy-all.sh` sweep exits non-zero on leftovers; budget alerts at 50/80/100% | Day-after Cost Explorer check |
| 10 | State file leak | Information disclosure | `*.tfstate*` and `*.tfvars` gitignored; state empty after destroy | Do not share repo archives with state files |
| 11 | CI abused to apply infra | Elevation | No apply workflow; CI uses dummy credentials, `contents: read` only | Actions pinned by SHA |
| 12 | Unrepudiable changes: no audit of who changed routes | Repudiation | Git history + PR review; CloudTrail not enabled in this account | Accepted; out of scope for a time-boxed window |