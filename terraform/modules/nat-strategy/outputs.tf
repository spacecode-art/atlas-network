output "nat_gateway_ids" {
  description = "Map of nat_gateways key to the created NAT Gateway ID"
  value       = { for k, v in aws_nat_gateway.this : k => v.id }
}

output "nat_gateway_public_ips" {
  description = "Map of nat_gateways key to the NAT Gateway's public (EIP) IP address"
  value       = { for k, v in aws_eip.nat : k => v.public_ip }
}