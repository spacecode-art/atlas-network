locals {
  common_tags = {
    ManagedBy = "terraform"
    Owner     = var.owner
  }
}

# ---------------------------------------------------------------------------
# Security group for the endpoint ENI. PrivateLink's actual access control
# lives here (and in the endpoint policy, not modeled yet) — this is the
# layer VPC Peering can't give you: scoped to one service, one CIDR, one
# port, not an entire VPC's routing table. See ADR-0003.
# ---------------------------------------------------------------------------
resource "aws_security_group" "endpoint" {
  name_prefix = "${var.name_prefix}-privatelink-"
  description = "Controls access to the ${var.service_name} Interface Endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from permitted CIDRs only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # No egress rule needed for the endpoint ENI itself — it only receives
  # inbound HTTPS and proxies to the backing service. Explicit empty
  # egress, not omission, matches the locked-down default SG pattern
  # used in atlas-foundation's networking module.
  egress = []

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-privatelink-sg"
  })
}

# Prerequisite for services (S3, DynamoDB) where AWS requires an existing
# Gateway endpoint before an Interface endpoint for the same service can
# enable private_dns_enabled. This resource is itself a Gateway endpoint,
# not PrivateLink — ADR-0003's "never Gateway" rule is about the endpoint
# this module exposes to consumers (aws_vpc_endpoint.this, always
# Interface), not about an internal prerequisite resource. Only created
# when the caller opts in via create_gateway_endpoint.
resource "aws_vpc_endpoint" "gateway_prerequisite" {
  count             = var.create_gateway_endpoint ? 1 : 0
  vpc_id            = var.vpc_id
  service_name      = var.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.gateway_endpoint_route_table_ids

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-privatelink-gateway-prereq"
  })
}

resource "aws_vpc_endpoint" "this" {
  vpc_id            = var.vpc_id
  service_name      = var.service_name
  vpc_endpoint_type = "Interface" # the endpoint this module actually exposes — never Gateway, see ADR-0003

  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-privatelink-endpoint"
  })

  depends_on = [aws_vpc_endpoint.gateway_prerequisite]
}