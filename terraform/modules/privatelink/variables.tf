variable "name_prefix" {
  description = "Prefix applied to all resource Name tags in this module"
  type        = string
  default     = "atlas-network"
}

variable "owner" {
  description = "Team or individual accountable for this resource (tagging policy requires this — see atlas-security policies/opa/tagging.rego)"
  type        = string
}

variable "vpc_id" {
  description = "VPC the Interface Endpoint's ENI is placed in (the consuming spoke, per ADR-0003)"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet(s) to place the endpoint ENI in — one per AZ for HA"
  type        = list(string)
}

variable "service_name" {
  description = <<-EOT
    The service this endpoint targets. Either an AWS-native service name
    (e.g. "com.amazonaws.us-east-1.s3") for the burst-deploy evidence in
    ADR-0003, or a VPC Endpoint Service name if this platform ever
    publishes its own — the module doesn't assume which.
  EOT
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks permitted to reach the endpoint on 443 — scope this to the consuming spoke's CIDR, not 0.0.0.0/0"
  type        = list(string)
}

variable "private_dns_enabled" {
  description = "Whether to enable private DNS resolution for the service's standard hostname inside this VPC"
  type        = bool
  default     = true
}

variable "create_gateway_endpoint" {
  description = <<-EOT
    Some AWS services (S3, DynamoDB) require a Gateway endpoint to already
    exist in the VPC before an Interface endpoint for the same service can
    set private_dns_enabled = true. Set true only for those services; for
    services without a Gateway endpoint type, leave false.
  EOT
  type    = bool
  default = false
}

variable "gateway_endpoint_route_table_ids" {
  description = "Route table IDs to associate the Gateway endpoint with — required if create_gateway_endpoint is true"
  type        = list(string)
  default     = []
}