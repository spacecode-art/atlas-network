#!/usr/bin/env bash
# IaC security scan. Same script locally (results committed as evidence) and in CI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${OUT:-docs/evidence/security-scan}"
mkdir -p "$OUT"
rc=0

command -v checkov >/dev/null || { echo "checkov required: pip install 'checkov>=3,<4'" >&2; exit 1; }

# Accepted findings are justified in ADR-0009. Add an ID here only with an ADR entry.
SKIP="CKV_AWS_130,CKV2_AWS_11"
args=(-d terraform --framework terraform --download-external-modules true --skip-check "$SKIP")
checkov "${args[@]}" --output json > "${OUT}/checkov.json" || rc=$?
checkov "${args[@]}" --output cli --compact --quiet > "${OUT}/checkov.txt" || true

if command -v trivy >/dev/null; then
  trivy config --format json --output "${OUT}/trivy.json" terraform || rc=$?
else
  echo "trivy not installed — skipped (install locally to include it in committed evidence)"
fi

if [[ "$rc" -ne 0 ]] && command -v jq >/dev/null; then
  echo "Checkov failed checks (check_id, resource, file):" >&2
  jq -r 'if type=="array" then .[0] else . end
         | .results.failed_checks[]
         | "  \(.check_id)  \(.resource)  \(.file_path)"' "${OUT}/checkov.json" >&2 || true
fi

# SOFT_FAIL=1 is an emergency override only; findings are triaged in ADR-0009.
if [[ "${SOFT_FAIL:-0}" == "1" ]]; then exit 0; fi
exit "$rc"