# ADR-0010: Reachability Analyzer Failed on Insufficient Permissions

## Status

Accepted

## Date

2026-10-03

---

## Context

The first full burst-deploy of the final design applied all 33 `core`
resources, including the VPC→TGW routes (9 min), and the six TGW route-table
assertions passed on real AWS: the hub RT learns both spoke CIDRs; dev and
prod RTs each see only the hub CIDR. Segmentation (ADR-0002) is proven by
that evidence (`2026-10-03-run1-ra-permissions/tgw-routes-*.json`).

All three Reachability Analyzer analyses returned `Status: failed`, message
"The request failed due to insufficient permissions." Teardown then left
three RA paths and analyses behind, because `DeleteNetworkInsightsPath`
refuses a path that still has analyses, and the verification sweep did not
check for RA resources.

## Decision

- Root cause 1: RA reads every resource on the path using the caller's
  credentials. The burst policy had the RA control-plane actions (and, since
  ADR-0009, `tiros:*`) but not ~17 read-only Describe/Get actions RA needs
  (NACLs, instances, VPN/peering/prefix lists, load balancers, ...). Added as
  the `ReachabilityAnalyzerRead` statement.
- Root cause 2: `preflight.sh` simulated only the actions the code calls
  directly, not the actions the service needs on our behalf. Added the RA
  read actions to the simulated set.
- Root cause 3: `destroy-all.sh` deleted RA paths without deleting their
  analyses first, and the sweep ignored RA. It now deletes analyses, then
  paths, runs this cleanup before the Terraform destroys, and sweeps for
  leftover paths.
- `capture-evidence.sh` now prints the analysis `StatusMessage` on failure.

## Consequences

- A failed RA run no longer leaves silent leftovers, and fails the sweep if
  it does.
- The permission list is derived from AWS's documented RA requirements and
  confirmed by the fresh burst result (see run 2 evidence).

## Lessons

When a managed service acts on your behalf, the permissions it needs from
your principal are not visible in your own code. Simulate against the
service's documented requirements, not just your call sites.