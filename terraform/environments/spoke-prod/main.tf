# Pinned to atlas-foundation v1.0.0 — see terraform/environments/hub/main.tf
# for why this is a Git ref, not a relative path.
module "vpc" {
  source = "git::https://github.com/spacecode-art/atlas-foundation.git//terraform/modules/networking?ref=v1.0.0"

  environment = "network-spoke-prod"
  owner       = var.owner
  vpc_cidr    = "10.102.0.0/16"

  # Two AZs, matching ADR-0004's per-AZ NAT Gateway strategy for prod —
  # each AZ's private subnet routes through its own gateway, so an AZ
  # outage doesn't take egress down for the surviving AZ.
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.102.0.0/24", "10.102.1.0/24"]
  private_subnet_cidrs = ["10.102.10.0/24", "10.102.11.0/24"]
}