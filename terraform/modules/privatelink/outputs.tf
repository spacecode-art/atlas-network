output "endpoint_id" {
  value = aws_vpc_endpoint.this.id
}

output "endpoint_dns_entries" {
  description = "Private DNS names resolvable inside the VPC once private_dns_enabled is true"
  value       = aws_vpc_endpoint.this.dns_entry
}

output "security_group_id" {
  value = aws_security_group.endpoint.id
}