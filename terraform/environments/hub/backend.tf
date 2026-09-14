terraform {
  required_version = ">= 1.11"

  # Local backend for now — this repo only validates via `terraform plan`,
  # never applies in CI (see README CI/CD section). The burst-deploy
  # (ADR-0005) will need this swapped to the same S3+DynamoDB remote
  # backend pattern atlas-foundation already proved out, since
  # environments/core's terraform_remote_state data sources need to read
  # this environment's real state, not a local file only this machine has.
  backend "local" {
    path = "terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # CI plans with dummy credentials (scripts/tf-check.sh) since this repo
  # never applies in CI. The AWS provider normally calls
  # sts:GetCallerIdentity as a preflight step to resolve the account ID,
  # even for a plan-only run — that call fails against dummy creds.
  # Skipping it here only disables that identity lookup; a real
  # burst-deploy still needs genuine credentials to create anything.
  skip_credentials_validation = true
  skip_requesting_account_id  = true

}