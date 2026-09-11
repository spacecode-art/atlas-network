# Pinned to atlas-foundation v1.0.0 — a Git ref, not a relative path, so a
# future breaking change to foundation's networking module can't silently
# break this environment. See the commit message on that tag for why.
module "vpc" {
  source = "git::https://github.com/spacecode-art/atlas-foundation.git//terraform/modules/networking?ref=v1.0.0"

  environment          = "network-hub"
  owner                = var.owner
  vpc_cidr             = "10.100.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs  = ["10.100.0.0/24", "10.100.1.0/24"]
  private_subnet_cidrs = ["10.100.10.0/24", "10.100.11.0/24"]
}