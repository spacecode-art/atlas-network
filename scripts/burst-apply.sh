#!/usr/bin/env bash
# Apply all four environments in dependency order (ADR-0005), with pipefail so
# a failed apply is never masked by `| tee`.
set -euo pipefail

: "${AWS_PROFILE:=atlas-network-burst}"
export AWS_PROFILE AWS_DEFAULT_REGION=us-east-1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EVIDENCE_DIR="${EVIDENCE_DIR:-docs/evidence/burst-deploy/$(date -u +%Y-%m-%d)}"
mkdir -p "$EVIDENCE_DIR"
start="$(date +%s)"

trap 'echo "APPLY FAILED — run ./scripts/destroy-all.sh NOW, debug from logs afterward." >&2' ERR

for env in hub spoke-dev spoke-prod core; do
  echo "=== applying ${env} @ $(date -u +%H:%M:%SZ) ===" | tee -a "${EVIDENCE_DIR}/apply-log.txt"
  terraform -chdir="terraform/environments/${env}" apply \
    -var-file="terraform.tfvars" -auto-approve -no-color -input=false \
    | tee -a "${EVIDENCE_DIR}/apply-log.txt"
done

echo "apply finished — elapsed $(( ($(date +%s) - start) / 60 )) min of 60"