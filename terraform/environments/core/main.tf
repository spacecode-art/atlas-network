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

  # Read-only via the endpoint. Default endpoint policy is full access.
  endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:ListBucket"]
      Resource  = "*"
    }]
  })
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

# ---------------------------------------------------------------------------
# VPC-side routes into the Transit Gateway (ADR-0002, ADR-0009).
# Without these, attachments + TGW route tables exist but no VPC subnet
# actually sends traffic to the TGW.
#   - spokes get a route to the HUB CIDR only, never to each other
#   - hub gets routes to each spoke CIDR
# ---------------------------------------------------------------------------
locals {
  hub_cidr    = "10.100.0.0/16"
  spoke_cidrs = { dev = "10.101.0.0/16", prod = "10.102.0.0/16" }

  spoke_to_hub_routes = merge([
    for env, ids in {
      dev  = data.terraform_remote_state.spoke_dev.outputs.private_route_table_ids
      prod = data.terraform_remote_state.spoke_prod.outputs.private_route_table_ids
    } : { for idx, id in ids : "${env}-${idx}" => id }
  ]...)

  hub_to_spoke_routes = merge([
    for idx, rt_id in data.terraform_remote_state.hub.outputs.private_route_table_ids : {
      for env, cidr in local.spoke_cidrs : "${idx}-${env}" => {
        route_table_id = rt_id
        cidr           = cidr
      }
    }
  ]...)
}

resource "aws_route" "spoke_to_hub" {
  for_each = local.spoke_to_hub_routes

  route_table_id         = each.value
  destination_cidr_block = local.hub_cidr
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  # Attachments must be "available" before a route can target the TGW.
  depends_on = [module.transit_gateway]
}

resource "aws_route" "hub_to_spoke" {
  for_each = local.hub_to_spoke_routes

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = module.transit_gateway.transit_gateway_id

  depends_on = [module.transit_gateway]
}