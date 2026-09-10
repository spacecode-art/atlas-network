# ADR-0001: CIDR Strategy for the Demo Topology

## Status

Accepted

## Date

2026-09-10

---

## Context

This repo needs a hub VPC and two spoke VPCs (dev, prod) to demonstrate Transit
Gateway routing and route-table segmentation. The CIDR ranges chosen for these
three VPCs matter for two reasons beyond "pick something that doesn't overlap
internally":

1. `atlas-foundation` already has a live design using `10.0.0.0/16` for its
   development account VPC (see `atlas-foundation/docs/adr/ADR-0001` and its
   architecture diagram). If this repo's demo topology were ever attached to
   the same Transit Gateway as a foundation VPC — which is a realistic future
   step, not a hypothetical — an overlapping range would make that literally
   impossible without re-addressing something already built.
2. A real platform team allocates CIDR space centrally, once, before any
   individual repo picks its own ranges. Picking ranges here without checking
   what foundation already claimed would be the same mistake a junior
   engineer makes on a real team: shipping a VPC that can't be connected to
   anything else without a re-IP project.

---

## Decision

This repo's demo topology uses the `10.100.0.0/16` – `10.102.0.0/16` block,
reserved specifically for `atlas-network`:

| VPC | CIDR | Role |
|---|---|---|
| Hub | `10.100.0.0/16` | Transit Gateway attachment point, PrivateLink endpoint |
| Spoke: dev | `10.101.0.0/16` | Attaches to hub, single-AZ NAT |
| Spoke: prod | `10.102.0.0/16` | Attaches to hub, per-AZ NAT |

`atlas-foundation` keeps `10.0.0.0/16`–`10.5.0.0/16` (management, security,
shared, dev, staging, prod — one /16 per account). `atlas-network` starts its
range at `10.100.0.0/16` with wide spacing, not `10.6.0.0/16`, so that
foundation can add more accounts later without ever needing to touch this
repo's range.

---

## Alternatives Considered

### Reuse `10.0.0.0/16`-adjacent ranges (e.g., `10.6.0.0/16` onward)

Advantages: tighter allocation, looks more "used."

Rejected because: it assumes foundation's account count is final. It isn't —
foundation's own roadmap defers security/staging/shared environments (see
foundation ADR-0014). Tight adjacency optimizes for a constraint that doesn't
exist yet and creates a real collision risk later.

### Use RFC 1918 `172.16.0.0/12` space to guarantee no collision by construction

Advantages: mechanically impossible to collide with anything in `10.0.0.0/8`.

Rejected because: mixing address families across repos in the same platform
is exactly the kind of inconsistency a senior reviewer flags — one team's
VPCs in `10.x`, another's in `172.x`, with no documented reason, reads as
accidental rather than designed. A single address family with reserved,
spaced-out blocks is the more disciplined choice, and it's what real
platform teams do (a CIDR allocation sheet, not a second address family, is
the standard fix for "we might collide").

---

## Consequences

- Any future repo needing its own demo topology must check this ADR (and
  foundation's) before claiming a range. Worth formalizing as a shared
  `docs/cidr-registry.md` at the platform level once a third repo needs one —
  not yet, with only two data points.
- If `atlas-network`'s hub is ever attached to `atlas-foundation`'s real TGW
  (a plausible Phase 10 reference-architecture exercise), no re-IP is needed.
- Each spoke gets a full `/16` despite only needing a handful of subnets for
  a demo. This is intentional — it mirrors how real orgs allocate (per
  environment, not per actual usage), and it keeps subnet math identical to
  foundation's own VPC module conventions.