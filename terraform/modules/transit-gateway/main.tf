locals {
  common_tags = {
    ManagedBy = "terraform"
    Owner     = var.owner
  }
}

# ---------------------------------------------------------------------------
# Transit Gateway
#
# default_route_table_association/propagation are both disabled here, not
# just left at their defaults — this is intentional per ADR-0002. If a
# future attachment is added and someone forgets to wire it into a
# dedicated route table, it fails closed (unreachable) instead of silently
# inheriting the TGW default table's permissive behavior.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "this" {
  description                    = "${var.name_prefix} hub-and-spoke Transit Gateway"
  amazon_side_asn                = var.amazon_side_asn
  auto_accept_shared_attachments = "disable"

  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-tgw"
  })
}

# ---------------------------------------------------------------------------
# Attachments
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.hub_vpc_id
  subnet_ids         = var.hub_subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-attach-hub"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  for_each = var.spokes

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-attach-${each.key}"
  })
}

# ---------------------------------------------------------------------------
# Route tables — one per spoke, plus one for the hub. Per ADR-0002, spokes
# never share a route table.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rtb-hub"
  })
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  for_each = var.spokes

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rtb-${each.key}"
  })
}

# ---------------------------------------------------------------------------
# Associations — each attachment sits in exactly one route table.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each = var.spokes

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}

# ---------------------------------------------------------------------------
# Propagations — this is where the segmentation from ADR-0002 actually
# lives:
#   - the hub's route table learns routes from EVERY spoke (so return
#     traffic from the hub back to any spoke works)
#   - each spoke's route table learns routes ONLY from the hub attachment
#     (so a spoke can reach the hub, but never another spoke)
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table_propagation" "hub_learns_spokes" {
  for_each = var.spokes

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_learns_hub" {
  for_each = var.spokes

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke[each.key].id
}