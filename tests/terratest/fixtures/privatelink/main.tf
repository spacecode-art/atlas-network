terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

module "privatelink" {
  source = "../../../../terraform/modules/privatelink"

  owner        = "terratest"
  vpc_id       = "vpc-0devtest00000000"
  subnet_ids   = ["subnet-0devtesta00000000"]
  service_name = "com.amazonaws.us-east-1.s3"

  # Deliberately NOT 0.0.0.0/0 — this is the value the test below
  # locks in place. If this default ever gets widened without anyone
  # noticing, the test catches it even though `terraform validate`
  # and `fmt` never would.
  allowed_cidr_blocks = ["10.101.0.0/16"]
}