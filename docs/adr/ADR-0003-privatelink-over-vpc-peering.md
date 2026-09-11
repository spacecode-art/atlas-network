# ADR-0003: PrivateLink Over VPC Peering for the Internal Service Path

## Status

Accepted

## Date

2026-09-11

---

## Context

The hub VPC needs to expose at least one service privately to spokes,
without that traffic ever crossing the public internet. Two AWS-native
options solve this: VPC Peering (route the spoke directly to the hub VPC)
or PrivateLink (an Interface VPC Endpoint in the spoke, backed by a VPC
Endpoint Service or an AWS-native service, with no direct route between
the VPCs at all).

This repo has already chosen Transit Gateway over a peering mesh for
spoke-to-spoke and spoke-to-hub *routing* (see the Technology Choices
table in the README). PrivateLink is a different layer entirely — it is
about exposing one specific *service*, not routing entire VPC CIDRs to
each other — so the TGW decision doesn't settle this one by itself.

This repo's connectivity layer is intentionally decoupled from any
specific workload (see the "opaque black box" framing below) — this ADR
is about the mechanism, not about a specific internal API this repo does
not build or own.

---

## Decision

Use a PrivateLink Interface VPC Endpoint, **consumer side only**, for any
service a spoke needs to privately reach in this repo's demo topology.
Concretely, the burst-deploy evidence targets an S3 (or DynamoDB) Gateway/
Interface Endpoint from `spoke-dev` — a real, AWS-native service, not a
custom workload built for this repo — because it proves the same
mechanics (endpoint policy scoping, private DNS resolution, security
group control) without requiring this repo to also stand up and maintain
a fake internal API purely to have something to point the endpoint at.

**Provider-side PrivateLink (a VPC Endpoint Service fronting a real or
mock NLB) is explicitly out of scope for this repo.** See Consequences.

The `terraform/modules/privatelink` module accepts a `service_name`
variable (an AWS service name like `com.amazonaws.us-east-1.s3`, or a
VPC Endpoint Service name if this platform ever builds its own) rather
than assuming any particular backing service — this keeps the module
reusable regardless of what it ends up pointing at.

---

## Alternatives Considered

### VPC Peering, hub to spoke, for the service path

Advantages: no per-hour/per-GB endpoint cost, simpler mental model, one
fewer AWS primitive to learn.

Rejected because: peering exposes the *entire* hub VPC CIDR to the peered
spoke — there is no way to scope a peering connection down to "just this
one service." That's a much larger blast radius than the segmentation
this repo has already committed to in ADR-0002. Peering is still the
right tool for some future paths (e.g., dev needing broad, ongoing access
to a shared-services VPC) — it is rejected here specifically because
"one service, tightly scoped" is exactly the case PrivateLink exists for.

### Model both consumer and provider side of PrivateLink

Advantages: more complete demonstration — shows understanding of
Endpoint Services, NLB target groups, and endpoint acceptance workflows,
not just how to consume someone else's service.

Rejected (deferred, not abandoned) because: the provider side requires
standing up a real or mock backend service whose only purpose is being
PrivateLink's target — infrastructure built to justify infrastructure,
not to serve a real need. That inflates this repo's burst-deploy scope
and budget (ADR-0005) without adding new PrivateLink-specific signal
beyond what the consumer side already proves. Revisit if `atlas-platform`
(Phase 6) ever publishes a real internal service this repo could
legitimately consume instead of mocking one.

---

## Consequences

- The PrivateLink module in this repo only ever creates
  `aws_vpc_endpoint` resources of type `Interface`, associated with a
  spoke VPC's subnets and security group — never an
  `aws_vpc_endpoint_service`.
- Burst-deploy evidence (ADR-0005) must show the endpoint successfully
  resolving via private DNS and a real API call (e.g., `aws s3 ls`
  from within the spoke) succeeding without traversing the NAT Gateway —
  provable via VPC Flow Logs showing no NAT ENI in the traffic path.
- Documented in the Future Roadmap: provider-side PrivateLink, fronting
  a real service once one exists in `atlas-platform`.