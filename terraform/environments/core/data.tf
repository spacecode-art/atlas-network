# Reads hub, spoke-dev, and spoke-prod's state — read-only, no write access
# to their infrastructure. This is the "state stitching" pattern: core owns
# connectivity (TGW, PrivateLink, NAT), the three VPC environments own their
# own infrastructure independently, and core is the only place that needs
# to know about all three at once.
#
# LOCAL-BACKEND LIMITATION: these paths only work when core is planned from
# the same machine that ran each environment's terraform init/plan, since
# they read local state files by relative path. A real burst-deploy needs
# all four environments on a shared remote backend (S3+DynamoDB, same
# pattern atlas-foundation already proved out) so this works regardless of
# machine. Tracked as a prerequisite in ADR-0005, not silently assumed away.
data "terraform_remote_state" "hub" {
  backend = "local"
  config = {
    path = "../hub/terraform.tfstate"
  }
}

data "terraform_remote_state" "spoke_dev" {
  backend = "local"
  config = {
    path = "../spoke-dev/terraform.tfstate"
  }
}

data "terraform_remote_state" "spoke_prod" {
  backend = "local"
  config = {
    path = "../spoke-prod/terraform.tfstate"
  }
}