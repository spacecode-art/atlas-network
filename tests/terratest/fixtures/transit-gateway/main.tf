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

module "transit_gateway" {
  source = "../../../../terraform/modules/transit-gateway"

  owner      = "terratest"
  hub_vpc_id = "vpc-0hubtest0000000000"
  hub_subnet_ids = [
    "subnet-0hubtesta000000000",
    "subnet-0hubtestb000000000",
  ]

  spokes = {
    dev = {
      vpc_id     = "vpc-0devtest00000000"
      subnet_ids = ["subnet-0devtesta00000000"]
      cidr_block = "10.101.0.0/16"
    }
    prod = {
      vpc_id     = "vpc-0prodtest0000000"
      subnet_ids = ["subnet-0prodtesta0000000"]
      cidr_block = "10.102.0.0/16"
    }
  }
}