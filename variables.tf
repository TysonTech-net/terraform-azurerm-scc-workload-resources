variable "subscription" {
  type        = string
  description = "The existing subscription ID to use."
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
