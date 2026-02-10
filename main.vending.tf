###############################################################################
# Locals - Virtual Network Configuration with Hub Connectivity
###############################################################################

locals {
  # Build virtual networks config with hub connectivity injected from platform_shared
  # For each region in var.vending, merge hub connectivity settings into virtual_networks
  vending_virtual_networks = {
    for region, config in var.vending : region => {
      for vnet_key, vnet in config.virtual_networks : vnet_key => merge(vnet, {
        # Hub peering (hub-and-spoke): inject hub VNet resource ID from platform_shared
        # Only set if we have a valid hub ID for this region, otherwise use tfvars value or null
        hub_network_resource_id = local.use_hub_and_spoke && contains(keys(local.hub_virtual_network_resource_ids), region) ? (
          local.hub_virtual_network_resource_ids[region]
        ) : vnet.hub_network_resource_id

        # vWAN connection: inject vWAN hub resource ID from platform_shared
        vwan_hub_resource_id = local.use_virtual_wan && contains(keys(local.virtual_wan_hub_resource_ids), region) ? (
          local.virtual_wan_hub_resource_ids[region]
        ) : vnet.vwan_hub_resource_id

        # Auto-enable hub peering only if we have a valid hub VNet ID (from remote state or tfvars)
        hub_peering_enabled = (
          local.use_hub_and_spoke && contains(keys(local.hub_virtual_network_resource_ids), region)
        ) ? vnet.hub_peering_enabled : (
          vnet.hub_network_resource_id != null && vnet.hub_network_resource_id != "" ? vnet.hub_peering_enabled : false
        )

        # Auto-enable vWAN connection only if we have a valid vWAN hub ID (from remote state or tfvars)
        vwan_connection_enabled = (
          local.use_virtual_wan && contains(keys(local.virtual_wan_hub_resource_ids), region)
        ) ? vnet.vwan_connection_enabled : (
          vnet.vwan_hub_resource_id != null && vnet.vwan_hub_resource_id != "" ? vnet.vwan_connection_enabled : false
        )

        # Inject DNS servers from platform_shared if not explicitly set (keyed by region)
        dns_servers = length(vnet.dns_servers) > 0 ? vnet.dns_servers : try(local.dns_server_ip_addresses[region], [])
      })
    }
  }
}

###############################################################################
# Module - Subscription Vending
###############################################################################

module "subscription_vending" {
  source   = "Azure/avm-ptn-alz-sub-vending/azure"
  version  = "0.1.1"
  for_each = var.vending

  # Required
  location = each.value.location

  # Subscription - use existing
  subscription_id = var.subscription

  # Resource Providers
  subscription_register_resource_providers_enabled      = each.value.subscription_register_resource_providers_enabled
  subscription_register_resource_providers_and_features = each.value.subscription_register_resource_providers_and_features

  # Resource Groups
  resource_group_creation_enabled = each.value.resource_group_creation_enabled
  resource_groups                 = each.value.resource_groups

  # Virtual Networks - use computed config with hub connectivity injected
  virtual_network_enabled = each.value.virtual_network_enabled
  virtual_networks        = local.vending_virtual_networks[each.key]

  # Role Assignments
  role_assignment_enabled = each.value.role_assignment_enabled
  role_assignments        = each.value.role_assignments

  # User Managed Identities
  umi_enabled             = each.value.umi_enabled
  user_managed_identities = each.value.user_managed_identities

  # Budgets
  budget_enabled = each.value.budget_enabled
  budgets        = each.value.budgets

  # Route Tables
  route_table_enabled = each.value.route_table_enabled
  route_tables        = each.value.route_tables

  # Network Security Groups
  network_security_group_enabled = each.value.network_security_group_enabled
  network_security_groups        = each.value.network_security_groups

  # Telemetry
  enable_telemetry  = var.enable_telemetry
  disable_telemetry = each.value.disable_telemetry

  # Wait timer
  wait_for_subscription_before_subscription_operations = each.value.wait_for_subscription_before_subscription_operations
}
