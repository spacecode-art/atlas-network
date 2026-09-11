# Consumed by environments/core via terraform_remote_state — this is the
# contract between "who owns the hub VPC" and "who owns connectivity."
# Changing these output names is a breaking change for core, same
# seriousness as changing a module's public interface.
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}