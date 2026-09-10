variable "name_prefix" {
  description = "Prefix applied to all resource Name tags in this module"
  type        = string
  default     = "atlas-network"
}

variable "owner" {
  description = "Team or individual accountable for this resource (tagging policy requires this — see atlas-security policies/opa/tagging.rego)"
  type        = string
}

variable "amazon_side_asn" {
  description = "ASN for the Amazon side of the Transit Gateway"
  type        = number
  default     = 64512
}

variable "hub_vpc_id" {
  description = "VPC ID of the hub VPC (where the PrivateLink-fronted service lives)"
  type        = string
}

variable "hub_subnet_ids" {
  description = "Subnet IDs in the hub VPC to attach the Transit Gateway to, one per AZ"
  type        = list(string)
}

variable "spokes" {
  description = <<-EOT
    Map of spoke VPCs to attach. Key is the spoke name (e.g. "dev", "prod"),
    used in resource naming and route table lookups. Each spoke gets its own
    dedicated TGW route table per ADR-0002 — spokes never see each other's
    CIDRs, only the hub's.
  EOT
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    cidr_block = string
  }))
}