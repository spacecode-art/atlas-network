# Pinned to atlas-foundation v1.0.0 — see terraform/environments/hub/main.tf
# for why this is a Git ref, not a relative path.
module "vpc" {
  source = "git::https://github.com/spacecode-art/atlas-foundation.git//terraform/modules/networking?ref=v1.0.0"

  environment = "network-spoke-dev"
  owner       = var.owner
  vpc_cidr    = "10.101.0.0/16"

  # Single AZ, deliberately — ADR-0004 puts dev on a single shared NAT
  # Gateway, so a second AZ's worth of subnets here would have nothing
  # to attach to and no purpose. Contrast with spoke-prod's two AZs.
  availability_zones   = ["us-east-1a"]
  public_subnet_cidrs  = ["10.101.0.0/24"]
  private_subnet_cidrs = ["10.101.10.0/24"]
}