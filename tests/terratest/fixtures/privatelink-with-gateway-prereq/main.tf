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

  allowed_cidr_blocks = ["10.101.0.0/16"]

  # Exercises the ADR-0007 fix path — without this, the S3-targeting
  # fixture above never touches the Gateway-prerequisite code at all.
  create_gateway_endpoint          = true
  gateway_endpoint_route_table_ids = ["rtb-0devtestprivate0000"]
}