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

## [2026-09-10]

### Added
- Repository initialized: README, ADR-0001 (CIDR strategy)
- ADR-0002: Transit Gateway route table segmentation