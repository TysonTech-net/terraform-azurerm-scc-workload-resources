variable "subscription" {
  type        = string
  description = "The existing subscription ID to use."
}

variable "naming" {
  type = object({
    env      = string
    workload = string
    instance = optional(string, "001")
  })
  description = <<DESCRIPTION
Naming convention variables used to auto-generate resource names.

Properties:
- `env` - Environment identifier (e.g., "prod", "dev", "test")
- `workload` - Workload identifier (e.g., "identity", "connectivity", "management")
- `instance` - Instance number, defaults to "001"

All resource names are auto-generated using this pattern unless explicitly overridden.
Example patterns:
- Resource Groups: rg-{workload}-{env}-{purpose}-{region_abbr}-{instance}
- Virtual Networks: vnet-{workload}-{env}-{region_abbr}-{instance}
- Subnets: snet-{purpose}-{region_abbr}-{instance}
- Route Tables: rt-{workload}-{env}-{region_abbr}-{instance}
- NSGs: nsg-{subnet_name}
- UMIs: id-{workload}-{env}-{region_abbr}-{instance}
- RSVs: rsv-{workload}-{env}-{region_abbr}-{instance}
- Key Vaults: kv{workload}{region_abbr}{instance}{random_suffix}

Example:
```hcl
naming = {
  env      = "prod"
  workload = "identity"
  instance = "001"
}
```
DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply across all resources."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Toggle to enable or disable telemetry for the deployed resources."
}

###############################################################################
# Connectivity Configuration
###############################################################################

variable "connectivity_type" {
  type        = string
  description = "The type of connectivity architecture used in platform_shared. Determines which hub resources to reference."
  validation {
    condition     = contains(["hub_and_spoke", "virtual_wan", "none"], var.connectivity_type)
    error_message = "connectivity_type must be one of: hub_and_spoke, virtual_wan, none"
  }
}

variable "hub_region_mapping" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Maps platform_shared hub keys (e.g., "primary", "secondary") to region names (e.g., "uksouth", "ukwest").
This enables the workload stack to correctly associate hub resources (VNets, Firewalls, etc.) with regions.

Example:
```hcl
hub_region_mapping = {
  primary   = "uksouth"
  secondary = "ukwest"
}
```
DESCRIPTION
}

###############################################################################
# Remote State Configuration - Platform Shared
###############################################################################

variable "platform_shared_state" {
  type = object({
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
    key                  = string
    subscription_id      = string
  })
  description = <<DESCRIPTION
Configuration for accessing the platform_shared Terraform remote state.

Properties:
- `resource_group_name` - The name of the resource group containing the storage account
- `storage_account_name` - The name of the storage account containing the state file
- `container_name` - The name of the blob container containing the state file
- `key` - The key (path) of the state file within the container
- `subscription_id` - The subscription ID where the storage account resides

Example:
```hcl
platform_shared_state = {
  resource_group_name  = "rg-alz-mgmt-state-uksouth-001"
  storage_account_name = "stoalzmgmtuks001"
  container_name       = "mgmt-tfstate"
  key                  = "terraform.tfstate"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
}
```
DESCRIPTION
}

###############################################################################
# Default Resource Toggles
###############################################################################

variable "enable_default_umi" {
  type        = bool
  default     = true
  description = "Enable creation of a default User Managed Identity per region for workload operations (backup, deployment, etc.)."
}

variable "enable_default_nsg" {
  type        = bool
  default     = true
  description = "Enable creation of a default NSG per subnet with Azure default rules recreated at priority 4000+."
}

variable "enable_default_route_table" {
  type        = bool
  default     = true
  description = "Enable creation of a default route table per region that routes all traffic (0.0.0.0/0) to the hub firewall. Only applies when connectivity_type is 'hub_and_spoke'."
}

variable "enable_default_role_assignment" {
  type        = bool
  default     = false
  description = "Enable creation of a default Contributor role assignment for the subscription using the specified principal."
}

variable "default_contributor_principal_id" {
  type        = string
  default     = null
  description = "The principal ID (Object ID) of the group or user to assign Contributor role. Required when enable_default_role_assignment is true."
}

variable "enable_hub_gateway_route_table_updates" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Enable adding routes to the hub's gateway subnet route table for this spoke's VNet CIDRs.
This ensures traffic FROM on-premises TO this spoke goes through the Azure Firewall.
Only applies when connectivity_type is 'hub_and_spoke' AND the gateway route table exists.

Set to true when VPN or ExpressRoute gateways are deployed and you want on-premises
traffic to spokes to be inspected by the firewall.

NOTE: Requires the gateway route table to be enabled in platform_shared.
DESCRIPTION
}

###############################################################################
# Hub Topology Inputs
###############################################################################
# v1.11.0 contract: the module reads a SINGLE output (`dns_server_ip_address`)
# from the consuming hub's remote state for the hub-router IP. Subnet CIDRs
# used by the default NSG inbound rules are supplied by workload tfvars below
# — the AVM hub-and-spoke pattern module has no native subnet-CIDR outputs and
# TF can't filter subnets by IP-in-CIDR, so workload-side input is required.
#
# `hub_router_private_ip_override` is optional (defaults to outputs.tf-supplied
# value). `hub_router_subnet_address_prefixes` and `bastion_subnet_address_prefixes`
# are REQUIRED when their respective default NSG rules are enabled — a
# precondition on the consuming module fails plan with a clear error if missing.

variable "hub_router_private_ip_override" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Optional override for the hub router next-hop IP per region (the IP that workload
default route table sends 0.0.0.0/0 to). Map key = region name (e.g. "uksouth"),
value = IPv4 string. When set, beats the hub's `dns_server_ip_address` remote-state
output.

Use when the hub's accelerator-stock `dns_server_ip_address` output is null
(unusual) or when forcing a specific IP for an isolated test deployment.

Example:
```hcl
hub_router_private_ip_override = {
  uksouth = "172.16.0.100"
  ukwest  = "172.24.0.100"
}
```
DESCRIPTION

  validation {
    condition     = alltrue([for ip in values(var.hub_router_private_ip_override) : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip))])
    error_message = "Each value in hub_router_private_ip_override must be an IPv4 address (e.g. 172.16.0.100)."
  }
}

variable "hub_router_subnet_address_prefixes" {
  type        = map(list(string))
  default     = {}
  description = <<DESCRIPTION
Hub firewall / NVA front-end subnet CIDR(s) per region. Map key = region name,
value = list of CIDR strings (single-element list for typical AzFw or single-LB
NVA setups; multi-element for multi-NIC NVA clusters spanning multiple subnets).
Used as the `source_address_prefixes` for the default `AllowFirewallInBound` NSG rule.

REQUIRED when `enable_default_nsg = true` AND `enable_default_nsg_firewall_rule = true`.
A precondition on the consuming module fails plan if a region in `var.vending`
has no entry here when the rule is enabled.

Example (BBSWE NVA, trust subnet):
```hcl
hub_router_subnet_address_prefixes = {
  uksouth = ["172.16.0.96/27"]
  ukwest  = ["172.24.0.96/27"]
}
```

Example (moj AzFw, AzureFirewallSubnet):
```hcl
hub_router_subnet_address_prefixes = {
  uksouth = ["10.0.0.0/26"]
}
```
DESCRIPTION

  validation {
    condition = alltrue([
      for cidrs in values(var.hub_router_subnet_address_prefixes) : alltrue([
        for cidr in cidrs : can(cidrnetmask(cidr))
      ])
    ])
    error_message = "Every CIDR in hub_router_subnet_address_prefixes must be a valid IPv4 CIDR (e.g. \"172.16.0.96/27\")."
  }
}

variable "bastion_subnet_address_prefixes" {
  type        = map(list(string))
  default     = {}
  description = <<DESCRIPTION
Azure Bastion subnet CIDR(s) per region. Map key = region name, value = list of
CIDR strings. Bastion typically uses a single subnet (Azure-enforced name
`AzureBastionSubnet`), so single-element lists are normal. Used as the
`source_address_prefixes` for the default `AllowBastionInBound` NSG rule.

REQUIRED when `enable_default_nsg = true` AND `enable_default_nsg_bastion_rule = true`.
A precondition on the consuming module fails plan if a region in `var.vending`
has no entry here when the rule is enabled.

Example:
```hcl
bastion_subnet_address_prefixes = {
  uksouth = ["172.16.0.0/26"]
  ukwest  = ["172.24.0.0/26"]
}
```
DESCRIPTION

  validation {
    condition = alltrue([
      for cidrs in values(var.bastion_subnet_address_prefixes) : alltrue([
        for cidr in cidrs : can(cidrnetmask(cidr))
      ])
    ])
    error_message = "Every CIDR in bastion_subnet_address_prefixes must be a valid IPv4 CIDR (e.g. \"172.16.0.0/26\")."
  }
}

variable "enable_default_nsg_firewall_rule" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
When true, the default NSG includes an `AllowFirewallInBound` rule at priority 3999
that allows inbound from `var.hub_router_subnet_address_prefixes[region]`.

Set to false for PaaS-only workloads that don't receive return traffic from the hub
firewall/NVA (e.g. Nerdio's App Service + PE chain). When false, the rule is still
emitted for type stability but its source is `["0.0.0.0/32"]` (non-matchable), making
it a no-op. The `hub_router_subnet_address_prefixes` variable becomes optional.

Ignored when `enable_default_nsg = false`.
DESCRIPTION
}

variable "enable_default_nsg_bastion_rule" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
When true, the default NSG includes an `AllowBastionInBound` rule at priority 4000
that allows TCP 22/3389 inbound from `var.bastion_subnet_address_prefixes[region]`.

Set to false for workloads with no Bastion-reachable admin path (PaaS-only, or
workloads using Just-In-Time access only). When false, the rule is still emitted
for type stability but its source is `["0.0.0.0/32"]` (non-matchable), making it
a no-op. The `bastion_subnet_address_prefixes` variable becomes optional.

Ignored when `enable_default_nsg = false`.
DESCRIPTION
}

###############################################################################
# Default NSG Rule Extensions
###############################################################################

variable "additional_nsg_rules" {
  type = map(map(object({
    access                       = string
    description                  = optional(string)
    destination_address_prefix   = optional(string)
    destination_address_prefixes = optional(set(string))
    destination_port_range       = optional(string)
    destination_port_ranges      = optional(set(string))
    direction                    = string
    name                         = string
    priority                     = number
    protocol                     = string
    source_address_prefix        = optional(string)
    source_address_prefixes      = optional(set(string))
    source_port_range            = optional(string)
    source_port_ranges           = optional(set(string))
  })))
  default     = {}
  description = <<DESCRIPTION
Additional NSG rules merged additively into the orchestrator-generated default NSG for matching
subnets. Keyed first by the default NSG key (format `nsg-{region}-{vnet_key}-{subnet_key}` — same
keys as `local.default_network_security_groups` in main.vending.tf), then by rule key.

Use this to add bespoke allow/deny rules to a default NSG without re-enumerating the entire
default rule set. For the common case of restoring AllowVnetInBound on a plink subnet hosting
consumer private endpoints, prefer the ergonomic per-subnet `allow_vnet_inbound = true` flag
in the vending subnet schema rather than this map.

This is ignored when `enable_default_nsg = false` for the subscription — in that case provide a
full custom NSG via `vending.<region>.network_security_groups`.

Example:
```hcl
additional_nsg_rules = {
  "nsg-uksouth-workload-plink" = {
    AllowKvOutbound = {
      name                       = "AllowKvOutbound"
      access                     = "Allow"
      direction                  = "Outbound"
      priority                   = 3950
      protocol                   = "Tcp"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "*"
      destination_address_prefix = "AzureKeyVault.UKSouth"
      destination_port_range     = "443"
    }
  }
}
```
DESCRIPTION
}
