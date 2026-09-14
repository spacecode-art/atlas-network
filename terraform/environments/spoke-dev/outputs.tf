# Consumed by environments/core via terraform_remote_state — same contract
# as the hub environment's outputs.
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Needed by environments/core to place spoke-dev's NAT Gateway"
  value       = module.vpc.public_subnet_ids
}