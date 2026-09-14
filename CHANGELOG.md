# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Repository governance files (`.editorconfig`, `.gitignore`, `LICENSE`,
  `CONTRIBUTING.md`) — present on disk since repo init but never committed
- `transit-gateway` module implementing ADR-0002's per-spoke route table
  segmentation (hub + dev/prod spokes, default TGW route table left
  unused so any future attachment fails closed instead of inheriting
  permissive behavior)
- CI: `.github/workflows/terraform-plan.yml` running `fmt`/`validate`/`plan`
  on every PR touching Terraform, backed by `scripts/tf-check.sh` so the
  same checks are reproducible locally. `core` runs `validate` only, not
  `plan` — it depends on `hub`/`spoke-dev`/`spoke-prod`'s real state via
  `terraform_remote_state`, which doesn't exist in a fresh checkout; see
  the comment in `scripts/tf-check.sh` and ADR-0005
- ADR-0005: burst-deploy scope, 60-minute time limit, $5 dollar ceiling,
  and required billing-safety setup (dedicated IAM user, AWS Budget
  alerts, no root credentials) for the one permitted live deployment in
  this repo
- ADR-0005 correction: `atlas-foundation`'s S3 remote-state bucket is
  MiniStack-only (test credentials, localhost endpoints), not a real AWS
  resource — cannot be reused as originally assumed. A dedicated
  real-AWS backend bootstrap is now a documented prerequisite instead.

## [2026-09-10]

### Added
- Repository initialized: README, ADR-0001 (CIDR strategy)
- ADR-0002: Transit Gateway route table segmentation