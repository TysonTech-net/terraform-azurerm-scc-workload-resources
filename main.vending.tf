###############################################################################
# Locals - Dynamic Default Resources
###############################################################################

locals {
  # Helper to get region abbreviation with fallback to first 3 chars
  # Uses the avm-utl-regions module for official geo codes
  region_abbr_lookup = { for region, config in var.vending : region => try(local.get_region_abbr[region], substr(region, 0, 3)) }

  # Generate default UMI per region
  # Creates a workload identity that can be used for backup, deployment, etc.
  default_user_managed_identities = {
    for region, config in var.vending : "workload-${region}" => {
      # Auto-generated name: id-{workload}-{env}-{region_abbr}-{instance}
      name               = try(local.naming.user_managed_identity[region], "id-${var.naming.workload}-${var.naming.env}-${local.region_abbr_lookup[region]}-${var.naming.instance}")
      resource_group_key = try(keys(config.resource_groups)[0], null)
      location           = config.location
      tags               = var.tags
      role_assignments   = {}
    }
  }

  # Generate default route table per region (hub-and-spoke only)
  # Routes all traffic through the hub firewall with exact-match UDRs
  # to override Azure's default system routes and peering routes
  default_route_tables = {
    for region, config in var.vending : "rt-${region}" => {
      # Auto-generated name: rt-{workload}-{env}-{region_abbr}-{instance}
      name                          = try(local.naming.route_table[region], "rt-${var.naming.workload}-${var.naming.env}-${local.region_abbr_lookup[region]}-${var.naming.instance}")
      location                      = config.location
      resource_group_key            = try([for k, v in config.resource_groups : k if can(regex("network", lower(k)))][0], keys(config.resource_groups)[0])
      bgp_route_propagation_enabled = false # Disable BGP to force traffic through firewall
      tags                          = var.tags
      routes = merge(
        # Route 1: Default route for internet-bound traffic
        {
          to-internet = {
            name                   = "udr-to-internet"
            address_prefix         = "0.0.0.0/0"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = local.firewall_private_ip_addresses[region]
          }
        },
        # Route 2: Own VNet CIDRs (exact match to override VirtualNetwork route)
        # This forces intra-VNet traffic (between subnets) through the firewall
        {
          for vnet_key, vnet in config.virtual_networks :
          "to-own-vnet-${vnet_key}" => {
            name                   = "udr-to-own-vnet-${vnet_key}"
            address_prefix         = vnet.address_space[0]
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = local.firewall_private_ip_addresses[region]
          }
        }
      )
    } if local.use_hub_and_spoke && contains(keys(local.firewall_private_ip_addresses), region)
  }

  # Generate default NSG per subnet with default Azure rules at priority 4000+
  # Flatten: region -> vnet -> subnet into a single map of NSGs
  default_network_security_groups = merge([
    for region, config in var.vending : {
      for subnet_key in flatten([
        for vnet_key, vnet in config.virtual_networks : [
          for snet_key, snet in coalesce(vnet.subnets, {}) : {
            key        = "nsg-${region}-${vnet_key}-${snet_key}"
            subnet_key = snet_key
            subnet     = snet
            vnet_key   = vnet_key
            region     = region
            rg_key     = coalesce(vnet.resource_group_key, try([for k, v in config.resource_groups : k if can(regex("network", lower(k)))][0], keys(config.resource_groups)[0]))
            location   = coalesce(vnet.location, config.location)
          }
        ]
        ]) : subnet_key.key => {
        name               = "nsg-${subnet_key.subnet.name}"
        location           = subnet_key.location
        resource_group_key = subnet_key.rg_key
        tags               = var.tags
        # Rule sources, merged in order — later args win on key collision.
        # 1. Region-aware default rule set (firewall/bastion/azlb allows + deny-all + outbound).
        # 2. Per-subnet ergonomic AllowVnetInBound for plink subnets hosting consumer PEs.
        #    Opt in via the subnet's allow_vnet_inbound = true flag.
        # 3. Caller-supplied additional rules from var.additional_nsg_rules, keyed by NSG key.
        #
        # Each rule from any source is coerced through local.nsg_rule_schema so all rules end
        # up with the same 14-field shape. Without this coercion, per-NSG security_rules type
        # inference would diverge: NSGs with allow_vnet_inbound = true would have a different
        # rule-object type from NSGs without (because the inline AllowVnetInBound rule has fewer
        # fields than the typed var.additional_nsg_rules and the union shape inferred from the
        # default rules). That diverged inferred type makes default_network_security_groups
        # collapse to an object instead of a map, breaking the downstream merged_network_security_groups
        # conditional with "Inconsistent conditional result types".
        # AllowVnetInBound always emitted but source_address_prefix is conditional —
        # "VirtualNetwork" when the per-subnet allow_vnet_inbound flag is true, "0.0.0.0/32"
        # (non-matchable) otherwise. Always-emit keeps the security_rules type uniform across
        # all NSGs (otherwise per-NSG type variance breaks default_network_security_groups
        # map inference). The non-matchable IP makes the rule a no-op for subnets that don't
        # need it; no real traffic can have source 0.0.0.0/32.
        security_rules = merge(
          try(local.default_nsg_security_rules_by_region[subnet_key.region], local.default_nsg_security_rules),
          {
            AllowVnetInBound = {
              name                       = "AllowVnetInBound"
              priority                   = 3998
              direction                  = "Inbound"
              access                     = "Allow"
              protocol                   = "*"
              source_port_range          = "*"
              destination_port_range     = "*"
              source_address_prefix      = try(subnet_key.subnet.allow_vnet_inbound, false) ? "VirtualNetwork" : "0.0.0.0/32"
              destination_address_prefix = "VirtualNetwork"
              description                = "Allow intra-VNet inbound (active only when subnet.allow_vnet_inbound = true; non-matchable source 0.0.0.0/32 otherwise)"
            }
          }
        )
      }
    }
  ]...)

  # Generate default contributor role assignment for the subscription
  # Uses the workload and env naming convention as a reference
  default_role_assignments = {
    "contributor-${var.naming.workload}-${var.naming.env}" = {
      principal_id              = var.default_contributor_principal_id
      definition                = "Contributor"
      relative_scope            = ""
      principal_type            = "Group"
      definition_lookup_enabled = true
      use_random_uuid           = true
    }
  }
}

###############################################################################
# Locals - Virtual Network Configuration with Hub Connectivity
###############################################################################

locals {
  # Build virtual networks config with hub connectivity injected from platform_shared
  # Also inject route table and NSG references for subnets
  # Auto-generate names using naming convention if not explicitly set
  vending_virtual_networks = {
    for region, config in var.vending : region => {
      for vnet_key, vnet in config.virtual_networks : vnet_key => merge(vnet, {
        # Auto-generated name: vnet-{workload}-{env}-{region_abbr}-{instance}
        # Uses user-provided name if set, otherwise generates from naming convention
        name = coalesce(
          vnet.name,
          try(local.naming.virtual_network[region], "vnet-${var.naming.workload}-${var.naming.env}-${local.region_abbr_lookup[region]}-${var.naming.instance}")
        )

        # Hub peering (hub-and-spoke): inject hub VNet resource ID from platform_shared
        hub_network_resource_id = local.use_hub_and_spoke && contains(keys(local.hub_virtual_network_resource_ids), region) ? (
          local.hub_virtual_network_resource_ids[region]
        ) : vnet.hub_network_resource_id

        # vWAN connection: inject vWAN hub resource ID from platform_shared
        vwan_hub_resource_id = local.use_virtual_wan && contains(keys(local.virtual_wan_hub_resource_ids), region) ? (
          local.virtual_wan_hub_resource_ids[region]
        ) : vnet.vwan_hub_resource_id

        # Auto-enable hub peering only if we have a valid hub VNet ID
        hub_peering_enabled = (
          local.use_hub_and_spoke && contains(keys(local.hub_virtual_network_resource_ids), region)
          ) ? vnet.hub_peering_enabled : (
          vnet.hub_network_resource_id != null && vnet.hub_network_resource_id != "" ? vnet.hub_peering_enabled : false
        )

        # Auto-enable vWAN connection only if we have a valid vWAN hub ID
        vwan_connection_enabled = (
          local.use_virtual_wan && contains(keys(local.virtual_wan_hub_resource_ids), region)
          ) ? vnet.vwan_connection_enabled : (
          vnet.vwan_hub_resource_id != null && vnet.vwan_hub_resource_id != "" ? vnet.vwan_connection_enabled : false
        )

        # Auto-generated peering names: peer-{workload}-to-hub-{region_abbr}
        hub_peering_name_tohub = coalesce(
          vnet.hub_peering_name_tohub,
          try(local.naming.peering_to_hub[region], "peer-${var.naming.workload}-to-hub-${local.region_abbr_lookup[region]}")
        )

        # Auto-generated peering names: peer-hub-to-{workload}-{region_abbr}
        hub_peering_name_fromhub = coalesce(
          vnet.hub_peering_name_fromhub,
          try(local.naming.peering_from_hub[region], "peer-hub-to-${var.naming.workload}-${local.region_abbr_lookup[region]}")
        )

        # Auto-generated vWAN connection name: vhc-{workload}-{region_abbr}
        vwan_connection_name = coalesce(
          vnet.vwan_connection_name,
          try(local.naming.vwan_connection[region], "vhc-${var.naming.workload}-${local.region_abbr_lookup[region]}")
        )

        # Inject DNS servers from platform_shared if not explicitly set
        dns_servers = length(vnet.dns_servers) > 0 ? vnet.dns_servers : try(local.dns_server_ip_addresses[region], [])

        # Merge default tags with per-VNet tags
        tags = merge(var.tags, coalesce(vnet.tags, {}))

        # Inject route table and NSG references into subnets
        subnets = {
          for snet_key, snet in coalesce(vnet.subnets, {}) : snet_key => merge(snet, {
            # Auto-assign route table if hub-and-spoke, default RT is enabled, and not already set.
            # var.enable_default_route_table check is needed because default_route_tables is
            # populated whenever hub firewall IP is available — independent of the toggle. Without
            # this check, the subnet ends up with a dangling key_reference to an RT that
            # merged_route_tables (which DOES respect the toggle) doesn't actually create.
            route_table = snet.route_table != null ? snet.route_table : (
              var.enable_default_route_table && local.use_hub_and_spoke && contains(keys(local.default_route_tables), "rt-${region}") ? {
                id            = null
                key_reference = "rt-${region}"
              } : null
            )
            # Auto-assign NSG if not already set
            network_security_group = snet.network_security_group != null ? snet.network_security_group : {
              id            = null
              key_reference = "nsg-${region}-${vnet_key}-${snet_key}"
            }
          })
        }
      })
    }
  }

  # Merge default UMIs with user-provided UMIs
  # Only include the default UMI for THIS region, controlled by:
  # - Global flag: enable_default_umi
  # - Per-region flag: each.value.umi_enabled (allows disabling for DR regions)
  merged_user_managed_identities = {
    for region, config in var.vending : region => merge(
      # Only add default UMI if globally enabled AND per-region enabled (defaults to true)
      var.enable_default_umi && try(config.umi_enabled, true) ? {
        "workload-${region}" = local.default_user_managed_identities["workload-${region}"]
      } : {},
      config.user_managed_identities
    )
  }

  # Merge default route tables with user-provided route tables
  merged_route_tables = {
    for region, config in var.vending : region => merge(
      var.enable_default_route_table ? { for k, v in local.default_route_tables : k => v if startswith(k, "rt-${region}") } : {},
      config.route_tables
    )
  }

  # Merge default NSGs with user-provided NSGs
  merged_network_security_groups = {
    for region, config in var.vending : region => merge(
      var.enable_default_nsg ? { for k, v in local.default_network_security_groups : k => v if startswith(k, "nsg-${region}-") } : {},
      config.network_security_groups
    )
  }

  # Merge default role assignments with user-provided role assignments
  merged_role_assignments = {
    for region, config in var.vending : region => merge(
      var.enable_default_role_assignment && var.default_contributor_principal_id != null ? local.default_role_assignments : {},
      config.role_assignments
    )
  }

  # Compute resource group names with auto-generation
  # Auto-generates names if not provided: rg-{workload}-{env}-{purpose}-{region_abbr}-{instance}
  # Also injects default tags merged with per-RG tags
  computed_resource_groups = {
    for region, config in var.vending : region => {
      for rg_key, rg in config.resource_groups : rg_key => merge(rg, {
        name = coalesce(
          rg.name,
          # Auto-generate name based on key (network, management, etc.)
          rg_key == "network" ? try(local.naming.resource_group_network[region], "rg-${var.naming.workload}-${var.naming.env}-network-${local.region_abbr_lookup[region]}-${var.naming.instance}") :
          rg_key == "management" ? try(local.naming.resource_group_management[region], "rg-${var.naming.workload}-${var.naming.env}-mgmt-${local.region_abbr_lookup[region]}-${var.naming.instance}") :
          "rg-${var.naming.workload}-${var.naming.env}-${rg_key}-${local.region_abbr_lookup[region]}-${var.naming.instance}"
        )
        # Merge default tags with per-resource-group tags
        tags = merge(var.tags, coalesce(rg.tags, {}))
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

  # Resource Groups - use computed names with auto-generation
  resource_group_creation_enabled = each.value.resource_group_creation_enabled
  resource_groups                 = local.computed_resource_groups[each.key]

  # Virtual Networks - use computed config with hub connectivity, route tables, and NSGs injected
  virtual_network_enabled = each.value.virtual_network_enabled
  virtual_networks        = local.vending_virtual_networks[each.key]

  # Role Assignments - merge defaults with user-provided
  role_assignment_enabled = var.enable_default_role_assignment || each.value.role_assignment_enabled
  role_assignments        = local.merged_role_assignments[each.key]

  # User Managed Identities - merge defaults with user-provided
  umi_enabled             = var.enable_default_umi || each.value.umi_enabled
  user_managed_identities = local.merged_user_managed_identities[each.key]

  # Budgets
  budget_enabled = each.value.budget_enabled
  budgets        = each.value.budgets

  # Route Tables - merge defaults with user-provided
  route_table_enabled = var.enable_default_route_table || each.value.route_table_enabled
  route_tables        = local.merged_route_tables[each.key]

  # Network Security Groups - merge defaults with user-provided
  network_security_group_enabled = var.enable_default_nsg || each.value.network_security_group_enabled
  network_security_groups        = local.merged_network_security_groups[each.key]

  # Telemetry
  enable_telemetry  = var.enable_telemetry
  disable_telemetry = each.value.disable_telemetry

  # Wait timer
  wait_for_subscription_before_subscription_operations = each.value.wait_for_subscription_before_subscription_operations
}
