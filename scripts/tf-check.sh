#!/usr/bin/env bash
# Runs the exact checks CI runs, so a failure is reproducible locally
# before you ever open a PR. This script is the source of truth; the
# GitHub Actions workflow just calls it.
#
# Leaf environments (hub, spoke-dev, spoke-prod) own their own state and
# don't depend on anything else, so they get the full fmt + validate + plan
# treatment.
#
# `core` reads all three leaf environments' state via
# terraform_remote_state (terraform/environments/core/data.tf) — state
# that only exists after a real `terraform apply`, which this repo never
# runs in CI (see README CI/CD section). `core` is validated for syntax
# and type errors, but not planned here. A real plan for `core` only
# happens against live state during the burst-deploy runbook (ADR-0005).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEAF_ENVS=(hub spoke-dev spoke-prod)
STATE_DEPENDENT_ENVS=(core)

# Dummy, non-functional credentials — enough for the AWS provider to
# initialize. No resource or data source in this repo calls the AWS API
# during plan, so these never need to be real. See scripts/tf-check.sh
# comment above / README CI-CD section for why that's safe to state.
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-AKIAIOSFODNN7EXAMPLE}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export TF_IN_AUTOMATION=true
export TF_INPUT=false

echo "==> terraform fmt -check -recursive"
terraform fmt -check -recursive -diff "${ROOT}/terraform"

for env in "${LEAF_ENVS[@]}"; do
  dir="${ROOT}/terraform/environments/${env}"
  # Full init (not -backend=false): these use a real local backend (a
  # plain file on disk, no AWS involved), and `plan` needs it actually
  # initialized to run at all.
  echo "==> [${env}] terraform init"
  terraform -chdir="${dir}" init -input=false
  echo "==> [${env}] terraform validate"
  terraform -chdir="${dir}" validate
  echo "==> [${env}] terraform plan"
  # No real terraform.tfvars in CI (correctly gitignored — see .gitignore).
  # .tfvars.example is committed specifically so CI/new contributors have
  # a placeholder value to plan against.
  terraform -chdir="${dir}" plan -input=false -lock=false -var-file="terraform.tfvars.example"
done

for env in "${STATE_DEPENDENT_ENVS[@]}"; do
  dir="${ROOT}/terraform/environments/${env}"
  echo "==> [${env}] terraform init -backend=false"
  terraform -chdir="${dir}" init -backend=false -input=false
  echo "==> [${env}] terraform validate (plan skipped: depends on leaf envs' real state — see ADR-0005)"
  terraform -chdir="${dir}" validate
done

echo "==> All checks passed"