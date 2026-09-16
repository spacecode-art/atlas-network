module "transit_gateway" {
  source = "../../modules/transit-gateway"

  owner       = var.owner
  name_prefix = "atlas-network"

  hub_vpc_id     = data.terraform_remote_state.hub.outputs.vpc_id
  hub_subnet_ids = data.terraform_remote_state.hub.outputs.private_subnet_ids

  spokes = {
    dev = {
      vpc_id     = data.terraform_remote_state.spoke_dev.outputs.vpc_id
      subnet_ids = data.terraform_remote_state.spoke_dev.outputs.private_subnet_ids
      cidr_block = "10.101.0.0/16"
    }
    prod = {
      vpc_id     = data.terraform_remote_state.spoke_prod.outputs.vpc_id
      subnet_ids = data.terraform_remote_state.spoke_prod.outputs.private_subnet_ids
      cidr_block = "10.102.0.0/16"
    }
  }
}

module "privatelink" {
  source = "../../modules/privatelink"

  owner       = var.owner
  name_prefix = "atlas-network"

  # Consumer side lives in spoke-dev, per ADR-0003's burst-deploy scope
  # (an S3 Interface Endpoint proves the mechanism without a mock backend).
  vpc_id       = data.terraform_remote_state.spoke_dev.outputs.vpc_id
  subnet_ids   = data.terraform_remote_state.spoke_dev.outputs.private_subnet_ids
  service_name = "com.amazonaws.us-east-1.s3"

  # S3 requires a Gateway endpoint to exist before an Interface endpoint
  # for the same service can enable private_dns_enabled — see ADR-0007.
  create_gateway_endpoint          = true
  gateway_endpoint_route_table_ids = data.terraform_remote_state.spoke_dev.outputs.private_route_table_ids

  allowed_cidr_blocks = ["10.101.0.0/16"]
}

module "nat_dev" {
  source = "../../modules/nat-strategy"

  owner       = var.owner
  name_prefix = "atlas-network-dev"

  nat_gateways = {
    single = {
      public_subnet_id = data.terraform_remote_state.spoke_dev.outputs.public_subnet_ids[0]
    }
  }

  private_route_tables = {
    az_a = {
      route_table_id  = data.terraform_remote_state.spoke_dev.outputs.private_route_table_ids[0]
      nat_gateway_key = "single"
    }
  }
}

module "nat_prod" {
  source = "../../modules/nat-strategy"

  owner       = var.owner
  name_prefix = "atlas-network-prod"

  nat_gateways = {
    az-a = { public_subnet_id = data.terraform_remote_state.spoke_prod.outputs.public_subnet_ids[0] }
    az-b = { public_subnet_id = data.terraform_remote_state.spoke_prod.outputs.public_subnet_ids[1] }
  }

  private_route_tables = {
    az_a = {
      route_table_id  = data.terraform_remote_state.spoke_prod.outputs.private_route_table_ids[0]
      nat_gateway_key = "az-a"
    }
    az_b = {
      route_table_id  = data.terraform_remote_state.spoke_prod.outputs.private_route_table_ids[1]
      nat_gateway_key = "az-b"
    }
  }
}