# ADR-0008: IAM Policy Drift Between Repo and Live AWS, and a Fourth Describe* Gap

## Status

Accepted

## Date

2026-09-16

---

## Context

A second real burst-deploy attempt, run to exercise the ADR-0006/0007
fixes for real, surfaced two new problems distinct from anything in
those two ADRs: the repo's IAM policy file had silently drifted out of
sync with the live policy attached in AWS, in both directions, and a
fourth `Describe*` permission gap appeared — this time triggered by the
ADR-0007 fix itself being exercised against real AWS for the first time.

## Decision

### Root cause 1: merging a PR does not make an IAM fix live

ADR-0006 and ADR-0007's IAM fixes were both correctly written and merged
to `main` as JSON file changes. But an IAM policy file in Git and the
actual policy version attached to `atlas-network-burst-deploy` in AWS
are two independent things connected only by someone manually running
`aws iam create-policy-version --set-as-default`. That step was missed
after the ADR-0007 PR merged: `main` had the `ec2:DescribeAddressesAttribute`
fix, but the live policy was still pinned at v2, three versions behind.

The first `apply` of today's run failed on exactly the permission that
was supposedly already fixed — not a new bug, a sync failure. Confirmed via:

```bash
aws iam get-policy --profile default \
  --policy-arn arn:aws:iam::803347590852:policy/atlas-network-burst-deploy-policy \
  --query "Policy.DefaultVersionId"
```

returning `v2` when the repo file was already several fixes ahead.

**Fix applied:** ran `create-policy-version --set-as-default` directly
against AWS to bring the live policy to v3, then v4 as the next gap was
found (below).

### Root cause 2: drift also existed in the opposite direction

While reconciling the live policy, a second, older drift was found: the
live policy's guardrail statement had at some point been hardened
directly in AWS — renamed from `RegionGuardrail` to `DenyNonUsEast1EC2`
and given an added `Null: {"aws:RequestedRegion": "false"}` condition —
without that change ever being committed back to the repo. This is a
real security improvement (it closes a gap where EC2 API calls that omit
`RequestedRegion` from their request context would silently bypass the
region-deny guardrail), but it existed only in AWS, invisible to anyone
reading the repo as the source of truth.

**Fix applied:** overwrote the repo's IAM policy file with the exact
live document from `get-policy-version`, making the two byte-identical,
rather than hand-editing and risking a third drift.

### Root cause 3: a fourth `Describe*` gap, found by the ADR-0007 fix itself

ADR-0007's fix added a `create_gateway_endpoint` Gateway-type
`aws_vpc_endpoint` as a prerequisite for the S3 Interface endpoint. This
was exactly the exercising of code that had never before run against
real AWS — Terratest's plan-only fixture covers resource shape, not
live API permission calls. On first real `apply`, Terraform needed
`ec2:DescribePrefixLists` to resolve `com.amazonaws.us-east-1.s3` into
its prefix list ID for the Gateway endpoint's route table associations,
and that action was missing.

This is the same shape of gap as ADR-0006 and ADR-0007's IAM finding:
implicit provider read-back calls, not calls the Terraform config
explicitly asks for. Fourth instance of the same pattern.

**Fix applied:** added `ec2:DescribePrefixLists` to the `PrivateLinkEndpoint`
statement, pushed as policy version v4, confirmed via propagation wait
and successful re-apply.

### Verification

After the v4 fix, `./scripts/destroy-all.sh` completed cleanly through
all four environments with no permission errors, and the final
verification sweep (VPCs, TGWs, EIPs) returned empty. The repo's IAM
policy file was then confirmed byte-identical to the live v4 document
before committing, closing both directions of drift at once.

## Alternatives Considered

### Hand-edit the repo file to add just the one missing action

Rejected: this is exactly how the first drift (the guardrail rename) was
missed in the first place — a hand-edit only fixes the one difference
you already know about, not any others that have silently accumulated.
Overwriting with the live document and diffing is the only way to catch
both directions of drift in one pass.

### Treat this as covered by ADR-0006's precedent and skip a new ADR

Rejected: the root cause here is materially different from ADR-0006/0007.
Those were incomplete permission scoping. This is a **process** gap —
IAM fixes merging to `main` without a verified live-sync step — that
will recur on every future IAM change unless made an explicit step in
the workflow, not folded into an ADR about a different failure.

## Consequences

- **Process fix (mandatory):** every future IAM policy change must be
  verified live, not just merged. Add a step to the runbook: after any
  IAM policy PR merges, run
  `aws iam get-policy --query "Policy.DefaultVersionId"` and confirm it
  matches the version just pushed, before considering the fix complete.
- Repo's `iam/atlas-network-burst-deploy-policy.json` is now confirmed
  byte-identical to live policy v4 as of this ADR.
- Four `Describe*` gaps have now been found across three incidents
  (ADR-0006: 2, ADR-0007: 1, this ADR: 1). All four share the same
  shape — implicit provider read-back calls invisible to a config-only
  review. No further gaps are expected for the current module set, but
  any newly added Terraform resource type should be treated as
  guilty-until-proven-innocent for this failure mode on its first real
  `apply`, not assumed safe because `terraform plan` succeeded against
  MiniStack or a Terratest fixture.
- This ADR's incident, taken together with ADR-0006 and ADR-0007, is
  itself the strongest single piece of "Production First" evidence in
  the portfolio: a burst-deploy that succeeds on the first real attempt
  proves nothing about IAM-scoping discipline; one that fails, gets
  root-caused, and is fixed with a documented trail proves considerably
  more.