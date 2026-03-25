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
