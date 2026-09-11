locals {
  common_tags = {
    ManagedBy = "terraform"
    Owner     = var.owner
  }
}

# ---------------------------------------------------------------------------
# One Elastic IP + one NAT Gateway per entry in var.nat_gateways.
#
# Cost note (ADR-0004): each EIP here carries its own $0.005/hr charge as
# of Feb 2024, on top of the NAT Gateway's own $0.045/hr — a detail most
# cost estimates miss because it bills as "Public IPv4 Address," not as
# part of the NAT Gateway line item.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = var.nat_gateways

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = var.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.public_subnet_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nat-${each.key}"
  })

  # NAT Gateways must be created after their EIP; Terraform infers this
  # from the allocation_id reference above, but the AWS-documented
  # dependency also includes the subnet's Internet Gateway attachment,
  # which lives outside this module (in atlas-foundation's networking
  # module) — see this module's README for the wiring contract.
}

# ---------------------------------------------------------------------------
# Wire each private route table to its assigned NAT Gateway. This is the
# resource that actually implements "single-AZ dev, per-AZ prod" — it's
# just a matter of how many distinct nat_gateway_key values appear across
# var.private_route_tables.
# ---------------------------------------------------------------------------
resource "aws_route" "private_default" {
  for_each = var.private_route_tables

  route_table_id         = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.value.nat_gateway_key].id
}