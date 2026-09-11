# ADR-0004: NAT Strategy — Single-AZ for Dev, Per-AZ for Prod

## Status

Accepted

## Date

2026-09-11

---

## Context

Every private subnet that needs outbound internet access (package installs,
API calls to external services, etc.) needs a NAT Gateway somewhere. AWS
recommends one NAT Gateway per Availability Zone, so that an AZ failure
doesn't take down egress for workloads in other AZs. That recommendation is
correct for production and unnecessary spend for a low-traffic dev
environment — but "unnecessary spend" needs an actual number behind it, not
a vibe, to be a defensible architecture decision rather than a guess.

Current us-east-1 pricing (verified 2026-09-11, subject to AWS changing it):

| Component | Rate |
|---|---|
| NAT Gateway hourly | $0.045/hr (~$32.85/mo per gateway) |
| NAT Gateway data processing | $0.045/GB, both directions |
| Public IPv4 address (per NAT Gateway's EIP, since Feb 2024) | $0.005/hr (~$3.65/mo per gateway) |
| Cross-AZ data transfer (if a single shared NAT serves multiple AZs) | $0.01/GB, per direction |

So a single NAT Gateway's true idle cost is closer to **$36.50/mo**
(hourly + its EIP), not the $32.85 most cost tables quote — the EIP charge
is easy to miss because it doesn't show up as a "NAT Gateway" line item on
the bill, it shows up as "Public IPv4 Address."

---

## Decision

- **`spoke-dev`: one NAT Gateway, single-AZ**, shared by all private
  subnets in that VPC regardless of which AZ they're in. Cross-AZ traffic
  to reach it costs $0.01/GB, which is immaterial at dev traffic volumes.
- **`spoke-prod`: one NAT Gateway per AZ** (two, matching the two AZs
  already used for the hub/spoke subnet layout), eliminating both the
  cross-AZ charge and, more importantly, the single point of failure — an
  AZ outage in prod should not take down egress for the surviving AZ's
  workloads.

Monthly cost comparison, base charges only (excludes data processing,
which scales with actual traffic and is workload-dependent either way):

| | Gateways | Hourly+EIP cost |
|---|---|---|
| dev (single-AZ) | 1 | ~$36.50/mo |
| prod (per-AZ, 2 AZs) | 2 | ~$73.00/mo |

**The delta is ~$36.50/mo** — the cost of the availability guarantee prod
gets and dev doesn't. That's a small enough number that "prod should just
also use a single NAT to save money" is not a real argument; the
justification for per-AZ in prod is availability, not cost avoidance, and
this ADR should not be read as prod being expensive to justify skimping on
it.

---

## Alternatives Considered

### Single shared NAT Gateway for both dev and prod

Advantages: cheapest possible option, one gateway total.

Rejected because: this collapses the isolation this repo has already
committed to at the routing layer (ADR-0002) back down to a shared failure
domain at the NAT layer — a NAT Gateway outage or an accidental route table
change affecting the shared gateway would take down egress for both
environments simultaneously. Segmentation that stops at routing and doesn't
extend to shared infrastructure like NAT is only half-done.

### NAT Instances (self-managed EC2) instead of the managed NAT Gateway

Advantages: no per-hour or per-GB AWS-managed fee; a small instance can be
genuinely cheaper at low, steady traffic.

Rejected because: NAT Instances require patching, capacity planning, and
manual failover — operational burden this platform doesn't want to own for
a component whose entire job is "stay invisible." The managed NAT Gateway
is the correct trade of a known, predictable AWS fee for zero operational
overhead, which is the same reasoning this repo already applied when
choosing Transit Gateway over a self-managed routing appliance.

### VPC Endpoints instead of NAT wherever possible (not a replacement, a reduction)

Not really an alternative to this ADR's decision — this is a complementary
optimization already captured by ADR-0003. Traffic to AWS-native services
routed through an Interface Endpoint never touches NAT at all, which is
part of why ADR-0003's PrivateLink module exists. NAT is still needed for
genuine internet-bound traffic; endpoints just shrink what has to go
through it.

---

## Consequences

- `terraform/modules/nat-strategy` takes an `az_count` or equivalent input
  so the same module serves both environments — one call with a single
  subnet for dev, one call with two for prod — rather than two separate
  modules for what is fundamentally the same resource at different
  cardinality.
- Burst-deploy evidence (ADR-0005) should capture both environments in the
  same window if possible, so the Cost Explorer data pulled into
  `atlas-finops` shows the real (small) delta between them, not just a
  projected one.
- If dev traffic ever grows enough that the $0.01/GB cross-AZ charge on a
  single shared NAT exceeds the ~$36.50/mo cost of a second gateway
  (crossover is roughly 3.65 TB/month of cross-AZ NAT traffic, well beyond
  anything a demo/dev environment should ever produce), revisit this ADR.