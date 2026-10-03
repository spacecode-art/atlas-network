# ADR-0011: Reachability Analyzer dev→prod Analysis Failed (Open Finding)

## Status

Accepted (cause undetermined)

## Date

2026-10-03

---

## Context

After ADR-0010's permission fix, the second burst-deploy ran three
Reachability Analyzer (RA) analyses between TGW attachments:

- hub→dev: Succeeded, NetworkPathFound = true
- hub→prod: Succeeded, NetworkPathFound = true
- dev→prod: **Failed** — "The request failed due to insufficient Tiros
  permissions." The JSON's `NetworkPathFound: false` is a default on a
  failed analysis and is NOT evidence that the path is blocked.

The same IAM policy produced all three; `preflight.sh` had simulated
`tiros:CreateQuery`, `tiros:GetQueryAnswer` and `tiros:GetQueryExplanations`
as allowed, and both successful analyses used them.

## Decision

- dev→prod RA is not cited as evidence of segmentation.
- Segmentation (ADR-0002) is evidenced by the TGW route tables captured from
  real AWS: the dev RT contains only 10.100.0.0/16 and not 10.102.0.0/16;
  the prod RT contains only 10.100.0.0/16 and not 10.101.0.0/16
  (`tgw-routes-{hub,dev,prod}.json`, six assertions passed). RA hub→dev and
  hub→prod confirm the hub reaches both spokes.
- No further burst-deploy to chase this. A real-AWS experiment costs ~$0.60
  and the cause cannot be inspected: CloudTrail was not enabled in this
  account (cost discipline, ADR-0005).

## Hypotheses (unverified)

1. Producing the explanation for an unreachable path requires a permission
   that a reachable path does not.
2. The failure is specific to this source/destination pair or to an RA
   service-side limitation on blocked TGW-attachment paths.

## Consequences

- The capture script correctly flagged the failure (non-zero exit, status
  message printed) instead of recording a false "blocked" result.
- If RA evidence for a blocked path is wanted later: enable CloudTrail for
  the window, rerun, and read the denied action from the event.

## Lessons

A tool reporting "no path found" and a tool reporting "analysis failed" are
different results. Check the status before the verdict.