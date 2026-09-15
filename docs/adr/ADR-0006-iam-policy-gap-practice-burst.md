# ADR-0006: IAM Policy Gap Found During Practice Burst-Deploy

## Status

Accepted

## Date

2026-09-15

---

## Context

The `atlas-network-burst-deploy` IAM policy (v1, see ADR-0005) was scoped
by reading the Terraform config for the resources it *creates* — VPC,
subnets, TGW, PrivateLink endpoint, NAT. It under-scoped the actions
Terraform's AWS provider makes implicitly during `plan`/`destroy` to
read back state it didn't explicitly ask to create: security group rule
details and ENI enumeration ahead of subnet deletion.

This surfaced during the practice burst-deploy of `hub`, mid-`destroy`:
Terraform completed the IGW, both route tables, all four route table
associations, and the default SG cleanly, then hit `UnauthorizedOperation`
twice in the same category — once resolving security group rules, once
enumerating ENIs before it would allow the 4 subnets (and, transitively,
the VPC) to be deleted. Two failures with the same root cause in one
`destroy` run is a policy gap, not a one-off — retrying the same command
against the same policy would have failed identically a third time.

## Decision

### Root cause

`ec2:DescribeSecurityGroupRules` and `ec2:DescribeNetworkInterfaces` were
missing from the `VpcSubnetRouting` statement in
`iam/atlas-network-burst-deploy-policy.json`. Both are read-only
`Describe*` actions — same trust tier as everything already in that
statement — that Terraform's AWS provider calls implicitly, not actions
the Terraform config asks for directly. `terraform plan`-only CI never
catches this class of gap, because `plan` doesn't exercise the
destroy-time read path.

### Fix

Added both actions to the existing `VpcSubnetRouting` statement (no new
statement needed — same resource scope, same trust tier):

```json
"ec2:DescribeSecurityGroups",
"ec2:DescribeSecurityGroupRules",
"ec2:DescribeNetworkInterfaces",
"ec2:AuthorizeSecurityGroupIngress",
```

Applied as a new version of the customer-managed policy
(`create-policy-version` + set-as-default) rather than an inline policy
edit, since `atlas-network-burst-deploy` uses a managed policy — v2 is
now the default version.

### Why this would have recurred

The `privatelink` module creates a custom `aws_security_group`. Without
the `DescribeSecurityGroupRules` fix, the same gap would have blocked
`spoke-dev`'s destroy later in the same window — catching it on `hub`
first meant one fix covered both, instead of two more blind retries
burning the clock ADR-0005 budgets.

### Verification

After a 10-second propagation wait, `terraform destroy` resumed against
`hub`'s existing state (4 subnets + VPC still tracked as present) and
completed with no `403`/`UnauthorizedOperation` errors. Final check, not
just the Terraform log:

```bash
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=network-hub" \
  --query "Vpcs[].VpcId" --output text --profile default
```

Empty output — AWS's own view agrees with Terraform's state. Nothing
orphaned.

## Alternatives Considered

### Patch one permission, retry, patch the next if it fails again

Rejected: this is exactly the "death by a thousand cuts" retry loop
ADR-0005 warns against. Two failures from the same root cause justified
a full audit of the policy's `Describe*` coverage in one pass instead of
serial single-permission patches burning the 60-minute window.

### Grant broad `ec2:Describe*` instead of enumerating specific actions

Rejected: breaks the least-privilege intent of ADR-0005's IAM scoping.
Two named actions, added deliberately, is a smaller and more auditable
diff than a wildcard grant that also silently covers actions the config
never exercises.

## Consequences

- `iam/atlas-network-burst-deploy-policy.json` v2 is now the policy
  baseline for all future `atlas-network` burst-deploys — the solo
  recorded run starts from a policy already proven against a real
  `apply`+`destroy` cycle, not just `plan`.
- This class of gap (implicit provider read-permissions vs. explicit
  config permissions) is now a known risk for any future Atlas repo's
  burst-deploy IAM policy — worth a one-line callback in
  `atlas-security`'s least-privilege generation notes if that phase
  hasn't already covered it.
- The Testing Strategy gap noted in ADR-0005 (no automated test against
  a real TGW/PrivateLink `apply`) remains open — this incident is
  evidence *for* running the real burst, not a replacement for it.