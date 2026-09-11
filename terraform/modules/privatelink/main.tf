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

resource "aws_vpc_endpoint" "this" {
  vpc_id            = var.vpc_id
  service_name      = var.service_name
  vpc_endpoint_type = "Interface" # never Gateway — Gateway endpoints are not PrivateLink, see ADR-0003

  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-privatelink-endpoint"
  })
}