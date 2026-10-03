# Burst-Deploy Actuals

Filled in 2026-10-03 after the final run. Cost Explorer can lag up to ~24h; any later correction goes in a separate commit.

| Item | Modeled (ADR-0005) | Actual |
|---|---|---|
| Window (apply start → destroy complete) | ≤ 60 min | <N> min (final run, applied 12:22:41Z) |
| TGW attachments ×3 | $0.15 | $0.00 billed |
| Interface endpoint | $0.01 | $0.00 billed |
| NAT gateways ×3 + EIPs | ~$0.15 | $0.00 billed |
| Reachability Analyzer ×3 | ~$0.30 | $0.00 billed |
| **Total** | **~$0.61** | **$0.00 billed** |

- Run date (UTC): 2026-10-03 (final run applied 12:22:41Z)
- Credits balance before / after: <fill in, or "not recorded">
- Deviations and why: modeled cost is gross usage for one hour; billed cost was $0.00 per the billing console (<reason: credits applied / no charge>). At least 8 deploys in total (4 on 2026-10-03), so the per-run model understates total gross usage even though nothing was billed. 
- Screenshot: `docs/evidence/burst-deploy/<date>/cost-explorer.png`
- Feeds `atlas-finops` as a real (non-synthetic) data point.