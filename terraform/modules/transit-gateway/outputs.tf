output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "hub_attachment_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

output "spoke_attachment_ids" {
  description = "Map of spoke name to its TGW VPC attachment ID"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.spoke : k => v.id }
}

output "hub_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.hub.id
}

output "spoke_route_table_ids" {
  description = "Map of spoke name to its dedicated TGW route table ID"
  value       = { for k, v in aws_ec2_transit_gateway_route_table.spoke : k => v.id }
}