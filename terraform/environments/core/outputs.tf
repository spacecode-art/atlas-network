output "transit_gateway_id" {
  value = module.transit_gateway.transit_gateway_id
}

output "hub_attachment_id" {
  value = module.transit_gateway.hub_attachment_id
}

output "spoke_attachment_ids" {
  value = module.transit_gateway.spoke_attachment_ids
}

output "privatelink_endpoint_id" {
  value = module.privatelink.endpoint_id
}