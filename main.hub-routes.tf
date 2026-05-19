###############################################################################
# Hub Gateway Route Table Updates
###############################################################################
# This file adds routes to the hub's gateway subnet route table for spoke VNet CIDRs.
# This ensures traffic FROM on-premises TO spokes goes through the Azure Firewall.
#
# Routes added:
# - Spoke VNet CIDRs -> Firewall (to gateway route table, if enabled)
#
# NOTE: This is only needed when VPN or ExpressRoute gateways are deployed.
# The gateway route table must be enabled in platform_shared.
###############################################################################

locals {
  # Build routes to add to hub's gateway route table (for on-prem ingress)
  # Only created if gateway routing is enabled
  # Note: gateway_route_tables returns objects with {id, name} properties (or null if not enabled)
  spoke_routes_for_hub_gw_rt = merge([
    for region, config in var.vending : {
      for vnet_key, vnet in config.virtual_networks :
      "gw-route-${region}-${vnet_key}" => {
        name             = "udr-to-${var.naming.workload}-${vnet_key}-${local.region_abbr_lookup[region]}"
        route_table_id   = local.gateway_route_tables[region].id
        route_table_name = local.gateway_route_tables[region].name
        address_prefix   = vnet.address_space[0] # Primary CIDR
        firewall_ip      = local.firewall_private_ip_addresses[region]
        region           = region
        } if(
        local.use_hub_and_spoke &&
        contains(keys(local.gateway_route_tables), region) &&
        local.gateway_route_tables[region] != null &&
        try(local.gateway_route_tables[region].id, null) != null &&
        contains(keys(local.firewall_private_ip_addresses), region) &&
        var.enable_hub_gateway_route_table_updates
      )
    }
  ]...)
}

###############################################################################
# Add Spoke Routes to Hub Gateway Route Table (Conditional)
###############################################################################
# These routes ensure traffic FROM on-premises TO spokes goes through the firewall.
# Only created if var.enable_hub_gateway_route_table_updates is true and
# the gateway route table exists in platform_shared.

resource "azurerm_route" "spoke_to_hub_gw_rt" {
  for_each = local.spoke_routes_for_hub_gw_rt

  name                   = each.value.name
  resource_group_name    = split("/", each.value.route_table_id)[4]
  route_table_name       = each.value.route_table_name
  address_prefix         = each.value.address_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = each.value.firewall_ip
}
