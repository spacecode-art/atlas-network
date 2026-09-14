output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Needed by environments/core to place spoke-prod's per-AZ NAT Gateways"
  value       = module.vpc.public_subnet_ids
}


output "private_route_table_ids" {
  description = "Needed by environments/core to attach NAT Gateway routes"
  value       = module.vpc.private_route_table_ids
}