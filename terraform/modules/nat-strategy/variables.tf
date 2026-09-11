variable "name_prefix" {
  description = "Prefix applied to all resource Name tags in this module"
  type        = string
  default     = "atlas-network"
}

variable "owner" {
  description = "Team or individual accountable for this resource (tagging policy requires this — see atlas-security policies/opa/tagging.rego)"
  type        = string
}

variable "nat_gateways" {
  description = <<-EOT
    Map of NAT Gateways to create. Key is a short label (e.g. "az-a",
    "az-b", or just "single" for a dev-style shared gateway) referenced
    by private_route_tables to pick which gateway a given route table
    egresses through. One gateway (and one EIP) is created per entry —
    per ADR-0004, dev passes one entry, prod passes one per AZ.
  EOT
  type = map(object({
    public_subnet_id = string
  }))
}

variable "private_route_tables" {
  description = <<-EOT
    Map of private route tables that need a default (0.0.0.0/0) route
    added, pointing at one of the NAT Gateways defined in nat_gateways.
    Key is just a label for this resource; nat_gateway_key must match a
    key in the nat_gateways map. Multiple entries can point at the same
    nat_gateway_key (dev's shared-NAT case) or each at its own (prod's
    per-AZ case) — the module doesn't need to know which mode it's in.
  EOT
  type = map(object({
    route_table_id  = string
    nat_gateway_key = string
  }))
}