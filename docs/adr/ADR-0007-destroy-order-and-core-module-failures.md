# ADR-0007: Destroy Order, Core Module Bug, and Manual Cleanup During Burst-Deploy

## Status

Accepted

## Date

2026-09-15

---

## Context

Following ADR-0006's IAM fix, a second practice burst-deploy attempted the
full four-environment stack (`hub`, `spoke-dev`, `spoke-prod`, `core`).
Apply succeeded through `hub`, `spoke-dev`, and `spoke-prod`, but `core`
apply failed partway through, leaving real, billable resources live:
a Transit Gateway, three TGW VPC attachments (all stuck in `failed`
state), and three unassociated Elastic IPs. No NAT Gateways were
actually provisioned before the failure.

Recovering from this exposed three further problems beyond the immediate
apply failure, described below.

## Decision

### Root cause 1: `core` apply — cascading failure from one module bug

The `privatelink` module creates an `aws_vpc_endpoint` with
`private_dns_enabled = true` for the S3 Interface endpoint, but the
module never provisions the prerequisite S3 **Gateway** endpoint that
AWS requires before private DNS can be enabled on an Interface endpoint
for S3. This produced:

InvalidParameter: To set PrivateDnsOnlyForInboundResolverEndpoint to true,
the VPC must have a Gateway endpoint for the service.


That single failure left the TGW VPC attachments unable to reach
`available` state (they depend on the PrivateLink SG being fully
resolved in the same apply graph), so all three attachments timed out
at 10 minutes in `failing`/`pending`, compounding one root cause into
five reported errors.

A third, distinct IAM gap (`ec2:DescribeAddressesAttribute`, needed for
EIP read-back) fired in parallel and is corrected as part of this ADR's
policy update — same category of gap as ADR-0006, now the third instance.

**Fix:** `modules/privatelink/main.tf` must provision (or accept as a
data source) an S3 Gateway endpoint before creating the Interface
endpoint with `private_dns_enabled = true`, or set
`private_dns_enabled = false` if private DNS isn't actually required for
the burst-deploy's validation purpose. Tracked as a follow-up code fix,
separate from this ADR's process fixes.

### Root cause 2: Destroy run in the wrong order, breaking `core`'s state stitching

`core/data.tf` reads `hub`, `spoke-dev`, and `spoke-prod`'s state via
`terraform_remote_state` (local backend, by relative path — see the
LOCAL-BACKEND LIMITATION note already in that file). Apply order was
correct (`hub` → `spoke-dev` → `spoke-prod` → `core`, dependencies
resolve outward-in). Destroy was run in the same order instead of
reversed, deleting `hub` and `spoke-prod`'s state *before* `core` was
destroyed.

Once `hub` and `spoke-prod` state files were empty, `core`'s
`terraform_remote_state` data sources returned objects with no
attributes, and every resource in `core` that referenced
`data.terraform_remote_state.hub.outputs.*` or
`.spoke_prod.outputs.*` failed with `Unsupported attribute` errors.
`core destroy` could no longer run through Terraform at all — not a
partial failure, a total block.

**Fix:** destroy order must be the exact reverse of apply order:
`core` → `spoke-prod` → `spoke-dev` → `hub`. This is now enforced as a
documented, ordered runbook step (see Consequences) rather than left as
tribal knowledge.

### Root cause 3: Manual out-of-band cleanup required

With `core destroy` blocked by Root cause 2, the TGW, its three failed
attachments, and three orphaned EIPs could not be removed through
Terraform without first restoring `hub`/`spoke-prod` state — not viable
mid-window. These were deleted directly via AWS CLI/console instead,
verified against real state (`aws ec2 describe-transit-gateways`,
`describe-transit-gateway-vpc-attachments`, `describe-addresses`), all
confirmed empty afterward.

`spoke-dev`'s VPC also required a manual console deletion: a leftover
PrivateLink security group and the `failed` TGW attachment in that VPC
blocked `terraform destroy` from proceeding through the standard
dependency graph in the time available. After manual deletion, `terraform
state list` against `spoke-dev` returned empty — Terraform's own refresh
had already dropped the destroyed resources from state, so no
`terraform state rm` was needed. State and reality agreed.

**This is stated plainly, not smoothed over:** part of this burst-deploy's
cleanup did not go through `terraform destroy` end-to-end. Terraform's
destroy path became untrustworthy once `core`'s state stitching broke,
and continuing to fight it inside the recording window would have
violated ADR-0005's "destroy first, debug after" rule. Manual cleanup,
verified against AWS's own API afterward, was the correct call — a
`terraform destroy` that appears to succeed while actually leaving
resources behind would have been the worse outcome.

### Verification

Full sweep after all cleanup, both CLI-deleted and Terraform-destroyed
resources combined:

```bash
aws ec2 describe-vpcs --profile default --filters "Name=tag:Owner,Values=dennisk-atlas-portfolio" --query "Vpcs[].VpcId"
aws ec2 describe-transit-gateways --profile default --query "TransitGateways[?State!='deleted']"
aws ec2 describe-addresses --profile default --query "Addresses[]"
```

All three returned empty. Nothing orphaned, nothing billing.

## Alternatives Considered

### Restore `hub`/`spoke-prod` state from a backup and re-run `core destroy` properly

Rejected for this run: no state backup existed (local backend, no
versioning configured — itself a gap the LOCAL-BACKEND LIMITATION note
already flagged as a prerequisite for a real burst-deploy). Rebuilding
state by hand against live resources would have cost more window time
than the manual CLI cleanup, for the same end result.

### Keep fighting `terraform destroy` until it succeeds cleanly end-to-end

Rejected: this is the exact "death by a thousand cuts" pattern ADR-0005
and ADR-0006 both warn against. Once the state-stitching break made
`core destroy` structurally impossible without a state restore, no
amount of retrying would fix it — a different tool (raw AWS CLI) was
the correct escalation, not more retries of the same broken path.

## Consequences

- **Runbook fix (mandatory, not optional):** any future burst-deploy of
  this stack destroys in the exact reverse of apply order —
  `core` → `spoke-prod` → `spoke-dev` → `hub`. This should be codified as
  a single `destroy-all.sh` / Makefile target rather than left as a
  four-command sequence someone has to remember correctly under time
  pressure, since this ADR exists precisely because that didn't happen.
- `modules/privatelink/main.tf` has an open bug (missing Gateway
  endpoint prerequisite) that must be fixed before the next real
  burst-deploy attempts PrivateLink again — tracked separately from this
  ADR's process fixes.
- `iam/atlas-network-burst-deploy-policy.json` needs `ec2:DescribeAddressesAttribute`
  added (third `Describe*` gap in two runs) — same fix pattern as
  ADR-0006, applied as a new policy version.
- Local Terraform backend's lack of state versioning/backup is now a
  known, accepted gap (per ADR-0005's original acceptance), reconfirmed
  here as a real limitation that cost recovery time, not just a
  hypothetical one.
- This ADR is itself evidence of "Production First" per the philosophy
  in the Atlas Path plan: real infra recovery looks like reconciling
  Terraform state against ground truth via the provider's own API, not
  like every tool working exactly as designed on the first attempt.