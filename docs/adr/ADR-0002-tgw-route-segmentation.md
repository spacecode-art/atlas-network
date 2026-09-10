# ADR-0002: Transit Gateway Route Table Segmentation

## Status

Accepted

## Date

2026-09-10

---

## Context

With both `spoke-dev` and `spoke-prod` attached to the same Transit Gateway,
the default TGW behavior matters a lot: a Transit Gateway ships with a
**default route table**, and if every attachment associates with it and
propagates its routes into it, every spoke can reach every other spoke
automatically. That default is convenient and also exactly the kind of
implicit trust boundary that turns into a real incident — a compromised or
misconfigured dev workload getting a clean network path to prod is not a
hypothetical, it's one of the more common root causes in actual TGW-related
postmortems.

The question this ADR answers: should dev and prod be able to route to each
other through the hub by default?

---

## Decision

No. Each spoke gets its own TGW route table, not the TGW default route table:

- `rtb-hub-dev`: associated with the dev attachment. Propagates routes *from*
  dev, and *to* dev, only the hub CIDR (`10.100.0.0/16`) — enough for dev to
  reach the PrivateLink-fronted service in the hub, nothing else.
- `rtb-hub-prod`: associated with the prod attachment. Same pattern —
  propagates only the hub CIDR.
- The TGW's own default route table is left unused (no attachments
  associated with it), so nothing falls back to permissive behavior by
  accident if a future attachment forgets to specify a route table.

Mechanically, this means: dev's attachment propagates `10.101.0.0/16` only
into `rtb-hub-dev`, not into `rtb-hub-prod`. Prod's attachment propagates
`10.102.0.0/16` only into `rtb-hub-prod`. Neither route table has a route to
the other spoke's CIDR, so there is no path — not "blocked by a security
group," genuinely no route exists. That's the strongest version of this
control available: security groups are a second layer that can be
misconfigured; the absence of a route can't be bypassed by a permissive SG
rule somewhere downstream.

If dev and shared services need to talk later (a real future need — dev
pulling from a shared artifact registry, for example), that gets a
deliberate, explicit route addition to `rtb-hub-dev`, documented in its own
ADR when it happens. It does not get solved by merging dev and prod into one
shared route table for convenience.

---

## Alternatives Considered

### Single shared route table (TGW default) for both spokes

Advantages: simpler to set up, fewer Terraform resources.

Rejected because: this is the "flat network" anti-pattern at TGW scale — it
optimizes for setup speed over blast-radius containment, and blast-radius
containment is the entire reason to use TGW route tables instead of just
peering everything. A reviewer who's run TGW in production will look for
this exact segmentation first.

### Security groups only, shared route table

Advantages: still allows fine-grained control at the instance/ENI level.

Rejected because: SGs are a compensating control, not a substitute for route
segmentation. An SG rule can be loosened by a future PR without anyone
noticing the network-layer exposure it reopens; a missing route has no
equivalent "oops, one rule got too permissive" failure mode. Defense in
depth means both layers exist — but the route table is the primary control
here, not the SG.

---

## Consequences

- Adding a third spoke later means creating a third dedicated route table,
  not adding an attachment to an existing one — this scales linearly and
  deliberately, which is the intended tradeoff (more Terraform, less risk).
- The burst-deploy evidence for this repo must include a **negative test**:
  a Reachability Analyzer run from spoke-dev to spoke-prod, expected result
  "not reachable." A benchmark that only proves the *allowed* paths work is
  an incomplete proof — the denied path is the actual point of this ADR, and
  it needs the same evidence standard as everything that does get built.