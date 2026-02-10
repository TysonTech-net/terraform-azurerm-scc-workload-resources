terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.71.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription
}

provider "azapi" {
  subscription_id = var.subscription
}

###############################################################################
# Remote State - Platform Shared
###############################################################################

data "terraform_remote_state" "platform_shared" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.platform_shared_state.resource_group_name
    storage_account_name = var.platform_shared_state.storage_account_name
    container_name       = var.platform_shared_state.container_name
    key                  = var.platform_shared_state.key
    subscription_id      = var.platform_shared_state.subscription_id
    use_azuread_auth     = true
  }
}

###############################################################################
# Locals - Platform Shared Outputs
###############################################################################

locals {
  # Connectivity type flags
  connectivity_enabled = var.connectivity_type != "none"
  use_hub_and_spoke    = var.connectivity_type == "hub_and_spoke"
  use_virtual_wan      = var.connectivity_type == "virtual_wan"

  # Remote state outputs (with safe defaults)
  platform_shared_outputs = data.terraform_remote_state.platform_shared.outputs

  # Hub virtual network resource IDs - keyed by region (e.g., { "uksouth" = "/subscriptions/.../vnets/hub-uks", "ukwest" = "..." })
  # Use coalesce to handle null values when hub isn't deployed
  hub_virtual_network_resource_ids = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.hub_and_spoke_vnet_virtual_network_resource_ids, null),
    {}
  ) : {}

  # Virtual WAN sidecar virtual network resource IDs - for peering spoke VNets when using vWAN
  vwan_sidecar_virtual_network_resource_ids = local.use_virtual_wan ? coalesce(
    try(local.platform_shared_outputs.virtual_wan_sidecar_virtual_network_resource_ids, null),
    {}
  ) : {}

  # Virtual WAN hub resource IDs - for vWAN connections
  virtual_wan_hub_resource_ids = local.use_virtual_wan ? coalesce(
    try(local.platform_shared_outputs.virtual_wan_virtual_hub_resource_ids, null),
    {}
  ) : {}

  # Firewall private IPs for routing - keyed by region
  firewall_private_ip_addresses = local.connectivity_enabled ? (
    local.use_hub_and_spoke
    ? coalesce(try(local.platform_shared_outputs.hub_and_spoke_vnet_firewall_private_ip_address, null), {})
    : coalesce(try(local.platform_shared_outputs.virtual_wan_firewall_private_ip_address, null), {})
  ) : {}

  # DNS server IP addresses - keyed by region (e.g., { "uksouth" = ["10.0.0.4"], "ukwest" = ["10.1.0.4"] })
  dns_server_ip_addresses = local.connectivity_enabled ? coalesce(
    try(local.platform_shared_outputs.dns_server_ip_address, null),
    {}
  ) : {}

  # Route tables for user subnets (hub-and-spoke only) - for spoke VNets to route through firewall
  route_tables_user_subnets = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.hub_and_spoke_vnet_route_tables_user_subnets, null),
    {}
  ) : {}
}
