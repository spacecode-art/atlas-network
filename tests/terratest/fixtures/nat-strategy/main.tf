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

# Dev-style: one gateway, both route tables point at it.
module "nat_dev" {
  source = "../../../../terraform/modules/nat-strategy"

  owner       = "terratest"
  name_prefix = "atlas-network-dev"

  nat_gateways = {
    single = { public_subnet_id = "subnet-0devpublica0000000" }
  }

  private_route_tables = {
    az_a = { route_table_id = "rtb-0devprivatea000000", nat_gateway_key = "single" }
    az_b = { route_table_id = "rtb-0devprivateb000000", nat_gateway_key = "single" }
  }
}

# Prod-style: one gateway per AZ, each route table points at its own.
module "nat_prod" {
  source = "../../../../terraform/modules/nat-strategy"

  owner       = "terratest"
  name_prefix = "atlas-network-prod"

  nat_gateways = {
    az-a = { public_subnet_id = "subnet-0prodpublica000000" }
    az-b = { public_subnet_id = "subnet-0prodpublicb000000" }
  }

  private_route_tables = {
    az_a = { route_table_id = "rtb-0prodprivatea000000", nat_gateway_key = "az-a" }
    az_b = { route_table_id = "rtb-0prodprivateb000000", nat_gateway_key = "az-b" }
  }
}