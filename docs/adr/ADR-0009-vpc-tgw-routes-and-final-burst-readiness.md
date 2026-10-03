# ADR-0009: Missing VPC→TGW Routes, Reachability Analyzer Permissions, and Preflight Automation

## Status

Accepted

## Date

2026-09-29

---

## Context

A pre-burst code review of the repo after three practice burst-deploys
found problems that none of the practice runs could have surfaced, because
none of them ran Reachability Analyzer or sent a packet:

1. **No VPC route table targeted the Transit Gateway.** Attachments, TGW
   route tables, associations and propagations were all correct, but no
   `aws_route` with `transit_gateway_id` existed, so the README diagram's
   "`10.100.0.0/16 via TGW`" was not true of the deployed stack.
2. **The runbook's Reachability Analyzer commands had never been executed**
   and omitted `--protocol`, a required parameter. Its `sleep 15` was a
   guess, not a wait on analysis status.
3. **The IAM policy had no `tiros:*` permissions** (used by Reachability
   Analyzer) and a fifth gap in the same class as ADR-0006/0008, plus a
   pending uncommitted service-linked-role statement for the TGW.
4. **The cost model was wrong**: 3 TGW attachments and 3 NAT gateways are
   deployed, not 2 and 2, and Reachability Analyzer (~$0.10/analysis) was
   omitted. Corrected estimate: ~$0.61 for one hour (was ~$0.25).
5. **Teardown verification checked only VPCs, TGWs and EIPs.** ADR-0005
   names orphaned ENIs as the classic failure, but NAT gateways, VPC
   endpoints and ENIs were not swept.
6. The AWS account ID and owner tag were hard-coded in public files.

## Decision

- Add `aws_route.spoke_to_hub` and `aws_route.hub_to_spoke` to
  `environments/core`. Spokes get the hub CIDR only, never each other's.
- Add `tiros:CreateQuery`, `tiros:GetQueryAnswer`,
  `tiros:GetQueryExplanations` to the burst policy.
- Replace hand-typed runbook steps with scripts that fail loudly:
  `preflight.sh` (identity, repo-vs-live policy diff, IAM simulation,
  budget, leftover state, tf-check), `burst-apply.sh` (pipefail), 
  `capture-evidence.sh` (asserts TGW route table contents first, then
  Reachability Analyzer with status polling), `destroy-all.sh` (extended
  sweep, non-zero exit on leftovers).
- TGW route table contents are the primary segmentation evidence
  (deterministic); Reachability Analyzer is secondary, because its support
  for attachment-to-attachment paths is not something this repo has
  proven. A failed RA call never blocks teardown.
- Replace the account ID with `__ACCOUNT_ID__` in the committed IAM policy;
  redact it from evidence via `scripts/redact-evidence.sh`. Git history
  still contains it — an account ID is an identifier, not a secret.
- Add optional `endpoint_policy` to the privatelink module (S3 endpoint is
  read-only in `core`) and reject `0.0.0.0/0` in `allowed_cidr_blocks`.
- Add a Checkov scan to CI (soft-fail for the first triage pass).

## Consequences

- The final burst-deploy proves the design as documented, not a subset.
- Corrected budget: ~$0.61 modeled; the $5 ceiling is unchanged.
- The S3 interface endpoint remains a stand-in for the "internal API"
  PrivateLink use case in ADR-0003; publishing a real endpoint service is
  out of scope.
- Accepted scan findings (fill in after first Checkov run):
  - Checkov 3.3.22, 2026-10-03: 37 passed, 6 failed.
  - `CKV_TF_1` (module source not pinned to a commit), ×3: **fixed**, not
    accepted. `atlas-foundation` is now pinned by commit SHA (tag noted in a
    comment).
  - `CKV_AWS_130` (public subnets map public IPs on launch), ×2: **accepted**.
    The setting comes from the shared `atlas-foundation` networking module,
    where public subnets are intended to host internet-facing resources.
    This topology launches no instances; the public subnets only host NAT
    gateways, which use Elastic IPs and do not depend on this setting.
    Revisit upstream in `atlas-foundation`.
  - `CKV2_AWS_11` (VPC flow logging), ×1: **accepted**. Flow Logs are out of
    scope: the stack exists for one timed window with no workload traffic to
    observe, and enabling them adds IAM surface (README, Monitoring).

## Lessons

An architecture that is correct at every layer you tested can still be
unreachable at the layer you didn't. `plan` proves what Terraform will
create, not that packets flow.