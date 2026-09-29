# Incident Runbook — TGW Routing Black Hole

**Symptom:** a spoke cannot reach the hub (or the reverse), or a path that
should be blocked (dev→prod) is reachable.

**Note:** Flow Logs are not enabled (README, Monitoring). Diagnose from the
control plane.

## 1. Detect

- Reachability Analyzer path returns `NetworkPathFound` differing from the
  expected value in `scripts/capture-evidence.sh`, or
- TGW routes in state `blackhole`:
```bash
  aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id <rtb-id> \
    --filters "Name=state,Values=blackhole"
```

## 2. Diagnose (in this order)

1. Attachment state is `available`:
   `aws ec2 describe-transit-gateway-attachments`
2. Attachment is associated with exactly one TGW route table:
   `aws ec2 get-transit-gateway-route-table-associations --transit-gateway-route-table-id <rtb-id>`
3. Propagations are what ADR-0002 says (hub RT ← both spokes; each spoke RT ← hub only):
   `aws ec2 get-transit-gateway-route-table-propagations --transit-gateway-route-table-id <rtb-id>`
4. VPC side: the private route tables have the TGW route (`aws_route.spoke_to_hub` / `hub_to_spoke`):
   `aws ec2 describe-route-tables --route-table-ids <rtb-id>`
5. `terraform -chdir=terraform/environments/core plan -var-file=terraform.tfvars` — any drift shows here.

## 3. Roll back

- Revert the offending commit and re-apply `core` (never hand-edit routes
  and leave them). If unrecoverable inside the burst window: run
  `./scripts/destroy-all.sh` and debug from logs.

## 4. Verify

- Re-run `./scripts/capture-evidence.sh`; all assertions must print `ok:`.

## 5. Follow-up

- Blameless write-up as an ADR (see ADR-0006 through ADR-0009 for format).