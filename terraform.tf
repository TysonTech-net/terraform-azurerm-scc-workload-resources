terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.71.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

###############################################################################
# Data Sources
###############################################################################

# Get subscription details for dynamic naming
data "azurerm_subscription" "current" {}

# Get current Terraform identity (for Key Vault RBAC)
data "azurerm_client_config" "current" {}

###############################################################################
# Module - Azure Regions Utility
###############################################################################

# Provides region short names (geo codes) for naming conventions
module "avm_utl_regions" {
  source  = "Azure/avm-utl-regions/azurerm"
  version = "0.11.0"

  enable_telemetry = var.enable_telemetry
}

###############################################################################
# Random String - Key Vault Unique Suffix
###############################################################################

# Generate a 4-character random suffix for Key Vault names (must be globally unique)
# One random string per management region to ensure uniqueness
resource "random_string" "key_vault_suffix" {
  for_each = var.management

  length  = 4
  special = false
  upper   = false
  numeric = false
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
  # Subscription name for dynamic resource naming
  subscription_name = data.azurerm_subscription.current.display_name

  # Connectivity type flags
  connectivity_enabled = var.connectivity_type != "none"
  use_hub_and_spoke    = var.connectivity_type == "hub_and_spoke"
  use_virtual_wan      = var.connectivity_type == "virtual_wan"

  # Remote state outputs (with safe defaults)
  platform_shared_outputs = data.terraform_remote_state.platform_shared.outputs

  # Reverse the hub_region_mapping: region -> hub_key (e.g., "uksouth" -> "primary")
  # This allows looking up hub resources by region name
  region_to_hub_key = { for hub_key, region in var.hub_region_mapping : region => hub_key }

  # Raw hub outputs from platform_shared (keyed by hub key like "primary"/"secondary")
  hub_vnet_ids_raw = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.hub_and_spoke_vnet_virtual_network_resource_ids, null),
    {}
  ) : {}

  firewall_ips_raw = local.connectivity_enabled ? (
    local.use_hub_and_spoke
    ? coalesce(try(local.platform_shared_outputs.hub_and_spoke_vnet_firewall_private_ip_address, null), {})
    : coalesce(try(local.platform_shared_outputs.virtual_wan_firewall_private_ip_address, null), {})
  ) : {}

  dns_ips_raw = local.connectivity_enabled ? coalesce(
    try(local.platform_shared_outputs.dns_server_ip_address, null),
    {}
  ) : {}

  # Transform hub outputs: remap from hub key to region name using hub_region_mapping
  # If no mapping provided, pass through as-is (assumes keys are already region names)
  hub_virtual_network_resource_ids = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.hub_vnet_ids_raw[hub_key]
    if contains(keys(local.hub_vnet_ids_raw), hub_key)
  } : local.hub_vnet_ids_raw

  firewall_private_ip_addresses = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.firewall_ips_raw[hub_key]
    if contains(keys(local.firewall_ips_raw), hub_key)
  } : local.firewall_ips_raw

  # DNS server IPs - wrap in list (platform_shared outputs single IP string per region)
  dns_server_ip_addresses = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => [local.dns_ips_raw[hub_key]]
    if contains(keys(local.dns_ips_raw), hub_key)
    } : {
    for key, value in local.dns_ips_raw : key => [value]
  }

  # Virtual WAN sidecar virtual network resource IDs
  vwan_sidecar_virtual_network_resource_ids = local.use_virtual_wan ? coalesce(
    try(local.platform_shared_outputs.virtual_wan_sidecar_virtual_network_resource_ids, null),
    {}
  ) : {}

  # Virtual WAN hub resource IDs
  virtual_wan_hub_resource_ids = local.use_virtual_wan ? coalesce(
    try(local.platform_shared_outputs.virtual_wan_virtual_hub_resource_ids, null),
    {}
  ) : {}

  # Maintenance configuration resource IDs (from SCC custom module in platform_shared)
  # Used for Azure Update Manager patch schedules - keyed by config name
  scc_maintenance_configuration_resource_ids = coalesce(
    try(local.platform_shared_outputs.scc_maintenance_configuration_resource_ids, null),
    {}
  )

  # Automation Account ID (from management subscription, for ASR agent auto-update)
  # Cross-subscription: workload vaults reference the central Automation Account
  scc_automation_account_id = try(local.platform_shared_outputs.scc_automation_account_id, null)

  # Hub VNet address spaces (for exact-match UDRs to override peering routes)
  # Uses scc_hub_vnet_address_spaces which has resolved values from config module
  hub_vnet_address_spaces_raw = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.scc_hub_vnet_address_spaces, null),
    {}
  ) : {}

  hub_vnet_address_spaces = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.hub_vnet_address_spaces_raw[hub_key]
    if contains(keys(local.hub_vnet_address_spaces_raw), hub_key)
  } : local.hub_vnet_address_spaces_raw

  # Bastion subnet address prefixes (for bypass routes in spoke UDRs)
  # Enables symmetric routing by bypassing firewall for Bastion traffic
  bastion_subnet_address_prefixes_raw = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.scc_bastion_subnet_address_prefixes, null),
    {}
  ) : {}

  bastion_subnet_address_prefixes = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.bastion_subnet_address_prefixes_raw[hub_key]
    if contains(keys(local.bastion_subnet_address_prefixes_raw), hub_key) && local.bastion_subnet_address_prefixes_raw[hub_key] != null
  } : local.bastion_subnet_address_prefixes_raw

  # Firewall subnet address prefixes (for NSG inbound rules)
  # Allows traffic from firewall to spokes (return traffic, inspected spoke-to-spoke, etc.)
  firewall_subnet_address_prefixes_raw = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.scc_firewall_subnet_address_prefixes, null),
    {}
  ) : {}

  firewall_subnet_address_prefixes = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.firewall_subnet_address_prefixes_raw[hub_key]
    if contains(keys(local.firewall_subnet_address_prefixes_raw), hub_key) && local.firewall_subnet_address_prefixes_raw[hub_key] != null
  } : local.firewall_subnet_address_prefixes_raw

  # Gateway route tables (conditional - only if gateway routing is enabled)
  gateway_route_tables_raw = local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.hub_and_spoke_vnet_route_tables_gateway, null),
    {}
  ) : {}

  gateway_route_tables = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.gateway_route_tables_raw[hub_key]
    if contains(keys(local.gateway_route_tables_raw), hub_key)
  } : local.gateway_route_tables_raw
}

###############################################################################
# Locals - Default NSG Rules (Azure defaults recreated at priority 4000+)
###############################################################################

locals {
  # Static outbound NSG rules (same for all regions)
  default_nsg_outbound_rules = {
    AllowVnetOutBound = {
      name                       = "AllowVnetOutBound"
      priority                   = 4000
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
      description                = "Allow outbound traffic to VNet"
    }
    AllowInternetOutBound = {
      name                       = "AllowInternetOutBound"
      priority                   = 4001
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "Internet"
      description                = "Allow outbound traffic to Internet (via firewall)"
    }
    DenyAllOutBound = {
      name                       = "DenyAllOutBound"
      priority                   = 4096
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      description                = "Deny all other outbound traffic"
    }
  }

  # Region-aware NSG rules - inbound rules use firewall/bastion subnet prefixes
  # These rules ensure:
  # - AllowFirewall: All traffic from firewall (covers return traffic, inspected spoke-to-spoke, etc.)
  # - AllowBastion: RDP/SSH from Bastion (bypasses firewall via UDR)
  # - AllowAzureLB: Azure health probes
  # - DenyAll: Block everything else
  default_nsg_security_rules_by_region = {
    for region in keys(var.vending) : region => merge(
      # Inbound rules (region-aware)
      {
        AllowFirewallInBound = {
          name                       = "AllowFirewallInBound"
          priority                   = 3999
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = try(local.firewall_subnet_address_prefixes[region], "10.0.0.0/26")
          destination_address_prefix = "VirtualNetwork"
          description                = "Allow inbound traffic from firewall (return traffic, inspected flows)"
        }
        AllowBastionInBound = {
          name                       = "AllowBastionInBound"
          priority                   = 4000
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = null
          destination_port_ranges    = ["22", "3389"]
          source_address_prefix      = try(local.bastion_subnet_address_prefixes[region], "10.0.0.64/26")
          destination_address_prefix = "VirtualNetwork"
          description                = "Allow RDP/SSH from Bastion (bypasses firewall via UDR)"
        }
        AllowAzureLoadBalancerInBound = {
          name                       = "AllowAzureLoadBalancerInBound"
          priority                   = 4001
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "AzureLoadBalancer"
          destination_address_prefix = "*"
          description                = "Allow inbound traffic from Azure Load Balancer"
        }
        DenyAllInBound = {
          name                       = "DenyAllInBound"
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          source_address_prefix      = "*"
          destination_address_prefix = "*"
          description                = "Deny all other inbound traffic"
        }
      },
      # Outbound rules (static)
      local.default_nsg_outbound_rules
    )
  }

  # Fallback for backwards compatibility - uses first region's rules
  default_nsg_security_rules = try(
    local.default_nsg_security_rules_by_region[keys(var.vending)[0]],
    {}
  )
}
