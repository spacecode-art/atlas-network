#!/usr/bin/env bash
# Replaces the AWS account ID in evidence files with <ACCOUNT_ID>.
set -euo pipefail
dir="${1:?usage: redact-evidence.sh <evidence-dir>}"
acct="$(aws sts get-caller-identity --query Account --output text --profile "${ADMIN_PROFILE:-default}")"
find "$dir" -type f \( -name '*.json' -o -name '*.txt' \) -print0 \
  | xargs -0 sed -i.bak "s/${acct}/<ACCOUNT_ID>/g"
find "$dir" -name '*.bak' -delete
echo "redacted account ID in ${dir}"