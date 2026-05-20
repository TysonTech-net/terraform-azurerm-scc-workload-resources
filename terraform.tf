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

  # Single hub contract: dns_server_ip_address from accelerator-stock outputs.tf.
  # The AVM hub-and-spoke pattern module's underlying output is topology-agnostic —
  # returns var.hub_virtual_networks.X.hub_virtual_network.hub_router_ip_address when
  # NVA mode, returns the deployed firewall's private IP when AzFw mode. Same value
  # is used as the VNet DNS server (typical hub-and-spoke pattern: firewall/NVA IS the
  # forwarder) AND as the next-hop IP for spoke 0.0.0.0/0 UDRs.
  hub_router_ips_raw = local.connectivity_enabled && local.use_hub_and_spoke ? coalesce(
    try(local.platform_shared_outputs.dns_server_ip_address, null),
    {}
    ) : (
    local.connectivity_enabled && local.use_virtual_wan ? coalesce(
      try(local.platform_shared_outputs.virtual_wan_firewall_private_ip_address, null), {}
    ) : {}
  )

  # Transform hub outputs: remap from hub key to region name using hub_region_mapping
  # If no mapping provided, pass through as-is (assumes keys are already region names)
  hub_virtual_network_resource_ids = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => local.hub_vnet_ids_raw[hub_key]
    if contains(keys(local.hub_vnet_ids_raw), hub_key)
  } : local.hub_vnet_ids_raw

  # Final region-keyed map. Caller override (region-keyed by design) beats the
  # hub-state lookup result on key collision. Override can also add regions the
  # hub state doesn't expose (e.g. a workload pointing at an isolated test hub).
  firewall_private_ip_addresses = merge(
    length(var.hub_region_mapping) > 0 ? {
      for hub_key, region in var.hub_region_mapping : region => local.hub_router_ips_raw[hub_key]
      if contains(keys(local.hub_router_ips_raw), hub_key)
    } : local.hub_router_ips_raw,
    var.hub_router_private_ip_override,
  )

  # DNS server IPs - wrap in list (platform_shared outputs single IP string per region).
  # Same source as firewall_private_ip_addresses — the hub router IP IS the VNet DNS server.
  dns_server_ip_addresses = length(var.hub_region_mapping) > 0 ? {
    for hub_key, region in var.hub_region_mapping : region => [local.hub_router_ips_raw[hub_key]]
    if contains(keys(local.hub_router_ips_raw), hub_key)
    } : {
    for key, value in local.hub_router_ips_raw : key => [value]
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

  # AMA User Assigned Managed Identity ID (from platform_shared policy defaults)
  # Injected into every VM's managed_identities so TF doesn't fight the Azure
  # Policy that assigns this UAMI to all VMs for Azure Monitor Agent.
  scc_ama_user_assigned_managed_identity_id = try(
    local.platform_shared_outputs.templated_inputs.management_group_settings.policy_default_values.ama_user_assigned_managed_identity_id,
    null
  )

  # Firewall/NVA subnet address prefixes (NSG AllowFirewallInBound source).
  # v1.11.0: no hub-state read — workload tfvars supplies the CIDR list per region
  # (no native AVM output exposes subnet CIDRs and IP-in-CIDR filtering isn't
  # feasible in pure HCL). Region keys are the region NAME, matching var.vending.
  firewall_subnet_address_prefixes = var.hub_router_subnet_address_prefixes

  # Bastion subnet address prefixes (NSG AllowBastionInBound source).
  # v1.11.0: same shape — workload tfvars supplies the CIDR list per region.
  bastion_subnet_address_prefixes = var.bastion_subnet_address_prefixes

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
  # Static outbound NSG rules (same for all regions).
  # Azure rule: source service tags ("VirtualNetwork", "*", "AzureLoadBalancer", "Internet")
  # and wildcards MUST use sourceAddressPrefix (singular). They are REJECTED at API level
  # if placed in sourceAddressPrefixes (plural). CIDR-only rules can use either field;
  # we use plural for the rules whose source is workload-tfvars-supplied (firewall+bastion).
  # For type-stable composition across the merged rule map, ALL rules declare BOTH fields —
  # exactly one is null per rule.
  default_nsg_outbound_rules = {
    AllowVnetOutBound = {
      name                       = "AllowVnetOutBound"
      priority                   = 4000
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      destination_port_ranges    = null
      source_address_prefix      = "VirtualNetwork"
      source_address_prefixes    = null
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
      destination_port_ranges    = null
      source_address_prefix      = "*"
      source_address_prefixes    = null
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
      destination_port_ranges    = null
      source_address_prefix      = "*"
      source_address_prefixes    = null
      destination_address_prefix = "*"
      description                = "Deny all other outbound traffic"
    }
  }

  # Region-aware default inbound NSG rules.
  # AllowFirewallInBound + AllowBastionInBound are gated by per-rule toggles
  # (var.enable_default_nsg_firewall_rule, var.enable_default_nsg_bastion_rule).
  # When a toggle is true, source_address_prefixes uses the workload-tfvars-supplied
  # CIDR list (var.hub_router_subnet_address_prefixes / var.bastion_subnet_address_prefixes).
  # When a toggle is false (or the CIDR var is missing for the region), source falls
  # through to ["0.0.0.0/32"] — a non-matchable singleton — keeping the rule shape
  # stable across NSGs without conditionally omitting the rule (which produced per-NSG
  # type variance in v1.10.x, see feedback-tf-type-stable-conditional-map).
  # Preconditions on the consuming subscription_vending module fail plan if a toggle
  # is true but the CIDR var is missing for a region.
  default_nsg_security_rules_by_region = {
    for region in keys(var.vending) : region => merge(
      {
        AllowFirewallInBound = {
          name                    = "AllowFirewallInBound"
          priority                = 3999
          direction               = "Inbound"
          access                  = "Allow"
          protocol                = "*"
          source_port_range       = "*"
          destination_port_range  = "*"
          destination_port_ranges = null
          source_address_prefix   = null
          source_address_prefixes = (
            var.enable_default_nsg_firewall_rule
            && try(length(local.firewall_subnet_address_prefixes[region]), 0) > 0
          ) ? local.firewall_subnet_address_prefixes[region] : ["0.0.0.0/32"]
          destination_address_prefix = "VirtualNetwork"
          description                = "Allow inbound from hub firewall/NVA subnet(s). Active when enable_default_nsg_firewall_rule=true AND var.hub_router_subnet_address_prefixes[region] is populated."
        }
        AllowBastionInBound = {
          name                    = "AllowBastionInBound"
          priority                = 4000
          direction               = "Inbound"
          access                  = "Allow"
          protocol                = "Tcp"
          source_port_range       = "*"
          destination_port_range  = null
          destination_port_ranges = ["22", "3389"]
          source_address_prefix   = null
          source_address_prefixes = (
            var.enable_default_nsg_bastion_rule
            && try(length(local.bastion_subnet_address_prefixes[region]), 0) > 0
          ) ? local.bastion_subnet_address_prefixes[region] : ["0.0.0.0/32"]
          destination_address_prefix = "VirtualNetwork"
          description                = "Allow RDP/SSH from Bastion subnet(s). Active when enable_default_nsg_bastion_rule=true AND var.bastion_subnet_address_prefixes[region] is populated."
        }
        AllowAzureLoadBalancerInBound = {
          name                       = "AllowAzureLoadBalancerInBound"
          priority                   = 4001
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          source_port_range          = "*"
          destination_port_range     = "*"
          destination_port_ranges    = null
          source_address_prefix      = "AzureLoadBalancer"
          source_address_prefixes    = null
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
          destination_port_ranges    = null
          source_address_prefix      = "*"
          source_address_prefixes    = null
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
