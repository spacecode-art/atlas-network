# ADR-0005: Burst-Deploy Scope, Time Limit, and Budget

## Status

Accepted

## Date

2026-09-14

---

## Context

Transit Gateway, PrivateLink, and NAT Gateway have no free tier — modeled
cost if this topology ran continuously is ~$180–220/mo (see README Cost
Model). Everywhere else in the Atlas platform, "zero-cost" means
"genuinely free." Here it means "spent on purpose, once, for a documented
reason, and torn down within the hour" — this ADR is what makes that a
rule instead of a vibe.

Two things make a real, if brief, deployment worth doing rather than
relying purely on `plan` and diagrams:

- MiniStack Community does not emulate Transit Gateway or PrivateLink
  (see README Testing Strategy). ADR-0002's route segmentation claim —
  `spoke-dev` cannot reach `spoke-prod` through the hub — has never been
  proven against a real control plane, only against `terraform plan`'s
  static graph.
- `core/data.tf`'s `terraform_remote_state` data sources currently read
  **local** `.tfstate` files from `hub`, `spoke-dev`, and `spoke-prod`.
  That only works on the machine that ran each environment's `apply` —
  a real burst-deploy needs all four environments on a shared remote
  backend, so `core` can actually resolve their outputs regardless of
  machine.
- **Correction (2026-09-14):** this ADR originally assumed
  `atlas-foundation`'s existing `atlas-terraform-state` S3 bucket could
  be reused directly. Verified false on inspection: that bucket was
  created against MiniStack (`provider "aws" { endpoints { s3 =
  "http://localhost:4566" } }`, `access_key/secret_key = "test"`), not
  real AWS — it doesn't exist as an actual AWS resource and has no
  companion DynamoDB lock table either. A real-AWS backend has to be
  bootstrapped from scratch for this repo; see Decision and Consequences
  below.

## Decision

### Scope — exactly what gets deployed, nothing more

Only what's already coded in `terraform/environments/{hub,spoke-dev,spoke-prod,core}`:

- hub VPC + 2 spoke VPCs (foundation networking module — already proven
  independently, not re-validated here)
- Transit Gateway with ADR-0002's per-spoke route segmentation
- One PrivateLink Interface Endpoint (S3, in `spoke-dev`, per ADR-0003's
  scope)
- NAT: single-AZ dev, per-AZ prod (ADR-0004)

No resource gets added "since we're already in there." Scope creep during
a live, billable window is precisely what this ADR exists to prevent.

### Backend — remote state prerequisite

Before this burst-deploy can run, two things have to happen, in order:

1. **Bootstrap a real-AWS S3 bucket + DynamoDB lock table**, purpose-built
   for `atlas-network` (`atlas-network-terraform-state` / a matching lock
   table) — not a reuse of `atlas-foundation`'s `atlas-terraform-state`
   bucket, which is MiniStack-only (see Context correction above). Same
   design as `atlas-foundation`'s bootstrap (versioning, encryption,
   public-access block), pointed at real AWS with real (scoped) IAM
   credentials instead of MiniStack test credentials.
2. **Swap all four environments' `backend.tf`** from `backend "local"` to
   `backend "s3"`, pointed at the new bucket/table, one key prefix per
   environment (`atlas-network/<env>/terraform.tfstate`).

Both are separate, trackable follow-up commits (see Consequences), not
part of this ADR's text.

### Time limit

**60 minutes**, wall-clock, from `terraform apply` on `hub` to a
confirmed `terraform destroy` across all four environments. A timer
starts before the first `apply`. Budget includes Reachability Analyzer
runs (typically under 5 minutes per path) and evidence screenshots. If
something breaks mid-window: destroy first, debug from the (free)
logs/plan output afterward. Never extend the window to "just try one more
thing."

### Dollar ceiling

**$5, hard**, self-enforced via the billing alert below — well above the
modeled cost of the window itself:

| Resource | Rate | ~1 hour |
|---|---|---|
| TGW attachments (×2) | $0.05/hr each | $0.10 |
| PrivateLink endpoint | $0.01/hr | $0.01 |
| NAT Gateways (×2, dev+prod-AZ-a) + EIPs | ~$0.045/hr + $0.005/hr each | ~$0.10 |
| Data processing | usage-based | negligible — no real traffic beyond Reachability Analyzer probes |
| **Total, ~1 hour** | | **~$0.25** |

The $5 ceiling isn't because $0.25 is a real risk — it's the threshold
that triggers the billing alert below, leaving margin for something going
wrong (a forgotten resource, a longer-than-planned window) without a slow
bleed going unnoticed.

### Billing safety (required before this burst-deploy runs, not optional)

- **IAM user, not root.** Dedicated `atlas-network-burst-deploy` IAM
  user, permissions scoped to exactly the EC2 VPC/TGW/NAT/Endpoint
  actions plus S3/DynamoDB backend access needed — no console access, no
  broader policy attached "to be safe." Keys sourced from local shell env
  vars only (`export AWS_ACCESS_KEY_ID=...`), never written to
  `terraform.tfvars`, never committed, never pasted into a GitHub Actions
  secret (CI stays plan-only against dummy creds — see
  `scripts/tf-check.sh`).
- **Root account:** MFA enabled, no root access keys exist. Root never
  touches this deploy.
- **AWS Budget:** a $10 budget with alerts at 50/80/100%, configured once
  at the account level and reused for every future burst-deploy across
  every Atlas repo — not repo-specific setup.
- **Post-window verification:** Cost Explorer checked the day after, not
  just trusted — confirms `terraform destroy` actually cleared everything.
  The classic burst-deploy failure mode is a forgotten Elastic IP or an
  orphaned ENI from a not-fully-released endpoint, not a runaway resource.

### Evidence captured (permanent, committed to the repo)

- Full `terraform apply` output
- AWS Reachability Analyzer results: hub→spoke-dev (reachable),
  hub→spoke-prod (reachable), **spoke-dev→spoke-prod (not reachable — the
  one result that actually proves ADR-0002 holds at the network layer,
  not just on paper)**
- Screenshots: TGW route tables (the segmented tables, not the default),
  PrivateLink endpoint status
- Full, timestamped `terraform destroy` confirmation output
- The real (small) Cost Explorer line item for the window, feeding
  `atlas-finops` as one genuine non-synthetic data point

All of it lands in `docs/evidence/burst-deploy/`, following the
step-by-step runbook at `docs/evidence/burst-deploy/README.md` — that
runbook is operational detail and doesn't belong in an ADR; this ADR sets
the rules it has to follow.

---

## Alternatives Considered

### Never burst-deploy — rely entirely on `plan`, diagrams, and the written cost model

Advantages: genuinely $0, zero risk.

Rejected because: the single most credible piece of evidence this repo
can produce — Reachability Analyzer proving `spoke-dev` cannot reach
`spoke-prod` — cannot be generated any other way. A design that's never
been checked against a real control plane is a materially weaker artifact
than one that has, and the real cost here is cents, not a genuine
tradeoff.

### Deploy and leave it running for several days for richer Cost Explorer data

Advantages: more FinOps data points, more realistic traffic patterns.

Rejected because: this directly contradicts the Cost Aware principle the
whole plan is built on. `atlas-finops`'s pipeline is validated by
correctness and data shape, not volume — a few hours of real line items
proves it ingests real CUR data correctly just as well as a week would,
without the sustained bill.

### Paid LocalStack Pro (or another paid TGW-capable emulator) instead of real AWS

Advantages: avoids AWS entirely, repeatable on demand.

Rejected because: it breaks the $0 constraint the whole plan is built
around (see the master plan's v2 changelog on why LocalStack was already
abandoned for MiniStack over exactly this issue). A one-time,
few-cents burst against real AWS is cheaper and more credible than a
recurring paid subscription to a tool whose entire value proposition is
"not real AWS."

---

## Consequences

- **Two follow-up commits required before this burst-deploy can run:**
  (1) bootstrap a real-AWS S3 bucket + DynamoDB lock table dedicated to
  `atlas-network` — `atlas-foundation`'s existing backend is MiniStack-only
  and cannot be reused, corrected above after being wrongly assumed
  reusable in this ADR's first draft; (2) swap `backend "local"` →
  `backend "s3"` (with DynamoDB locking) in all four environments'
  `backend.tf` to point at it. Both are the next tasks after this ADR is
  accepted.
- `docs/evidence/burst-deploy/README.md` (the runbook) and
  `docs/cost-model/burst-deploy-actuals.md` stay unwritten until the
  burst-deploy actually happens — this ADR sets the rules; it doesn't
  replace the runbook.
- The Testing Strategy gap (no Terratest against a real TGW/PrivateLink
  `apply`) stays open even after this burst-deploy. One evidence-capturing
  run is not a repeatable automated test and shouldn't be treated as
  closing that gap.
- If the time limit or dollar ceiling is ever exceeded in practice, that
  gets its own entry in the README's Postmortem Example section — not a
  quiet retroactive edit to this ADR.