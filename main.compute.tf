###############################################################################
# Locals - Compute Resource Names with Auto-Generation
###############################################################################

locals {
  # Helper to get region abbreviation for compute regions
  compute_region_abbr = { for region, config in var.compute : region => try(local.get_region_abbr[region], substr(region, 0, 3)) }

  # Build a lookup table for subnet names from vending config
  # This allows us to compute subnet IDs without waiting for module outputs
  vending_subnet_names = {
    for region, config in var.vending : region => {
      for vnet_key, vnet in config.virtual_networks : vnet_key => {
        for subnet_key, subnet in coalesce(vnet.subnets, {}) : subnet_key => subnet.name
      }
    }
  }

  # Get computed resource group names (network RG) for subnet ID construction
  vending_network_rg_names = {
    for region, config in var.vending : region => coalesce(
      try(config.resource_groups["network"].name, null),
      try(local.naming.resource_group_network[region], null),
      "rg-${var.naming.workload}-${var.naming.env}-network-${try(local.get_region_abbr[region], substr(region, 0, 3))}-${var.naming.instance}"
    )
  }

  # Get computed vnet names for subnet ID construction
  vending_vnet_names = {
    for region, config in var.vending : region => {
      for vnet_key, vnet in config.virtual_networks : vnet_key => coalesce(
        vnet.name,
        try(local.naming.virtual_network[region], null),
        "vnet-${var.naming.workload}-${var.naming.env}-${try(local.get_region_abbr[region], substr(region, 0, 3))}-${var.naming.instance}"
      )
    }
  }

  # Resolve subnet IDs for VM NICs based on subnet_reference
  # Also handles maintenance configuration via tags (dynamic scoping) or legacy explicit assignments
  # Computes subnet ID from: subscription, RG name, VNet name, and subnet name
  compute_vms_with_resolved_subnets = {
    for region, config in var.compute : region => {
      for vm_key, vm in config.vms : vm_key => merge(vm, {
        network_interfaces = {
          for nic_key, nic in vm.network_interfaces : nic_key => merge(nic, {
            ip_configurations = {
              for cfg_key, cfg in nic.ip_configurations : cfg_key => merge(cfg, {
                # Resolve subnet_id: use explicit subnet_id if provided, otherwise compute from reference
                subnet_id = cfg.subnet_id != null ? cfg.subnet_id : (
                  cfg.subnet_reference != null ? join("/", [
                    "/subscriptions/${var.subscription}",
                    "resourceGroups/${try(local.vending_network_rg_names[region], "")}",
                    "providers/Microsoft.Network/virtualNetworks/${try(local.vending_vnet_names[region][cfg.subnet_reference.vnet_key], "")}",
                    "subnets/${try(local.vending_subnet_names[region][cfg.subnet_reference.vnet_key][cfg.subnet_reference.subnet_key], "")}"
                  ]) : null
                )
              })
            }
          })
        }

        # Inject MaintenanceWindow tag for dynamic scoping
        # When maintenance_window is set, the tag enables automatic assignment via dynamic scope
        # This replaces the need for explicit maintenance_configuration_resource_ids
        tags = merge(
          coalesce(vm.tags, {}),
          try(vm.maintenance_window, null) != null ? {
            MaintenanceWindow = vm.maintenance_window
          } : {}
        )

        # Resolve maintenance configuration (legacy explicit assignments):
        # - If maintenance_window is set, skip explicit assignment (dynamic scope handles it)
        # - If maintenance_configuration_key is set, look up resource ID from platform_shared
        # - If maintenance_configuration_resource_ids is set, use directly
        # - Otherwise, leave as empty map (no maintenance config)
        maintenance_configuration_resource_ids = (
          # Skip explicit assignment when using dynamic scoping via maintenance_window tag
          try(vm.maintenance_window, null) != null ? {} :
          coalesce(
            # Option 1: Explicit resource IDs provided
            try(vm.maintenance_configuration_resource_ids, null),
            # Option 2: Key reference to platform_shared config
            try(vm.maintenance_configuration_key, null) != null ? {
              "default" = local.scc_maintenance_configuration_resource_ids[vm.maintenance_configuration_key]
            } : null,
            # Default: empty map (no maintenance config)
            {}
          )
        )
      })
    }
  }
}

###############################################################################
# Key Vault Credential Auto-Storage
#
# When compute_auto_credential_keyvault_enabled = true, VMs that don't specify
# an explicit admin_password get auto-generated credentials stored in the
# regional Key Vault deployed by the management module.
###############################################################################

locals {
  # Regions where Key Vault is enabled (uses the management variable, known at plan time).
  # Cannot use module output here because resource IDs are unknown on first plan.
  _kv_enabled_regions = toset([
    for region, config in var.management : region
    if try(config.deploy_management_key_vault, false)
  ])

  # Map of region -> Key Vault resource ID from the management module.
  # Only populated for regions where Key Vault was deployed.
  regional_kv_resource_ids = {
    for region in local._kv_enabled_regions :
    region => try(module.workload_management[region].management_kv_resource_id[0], null)
  }

  # Determine which VMs in which regions should get auto-generated credentials.
  # A VM qualifies when:
  # 1. compute_auto_credential_keyvault_enabled = true
  # 2. Key Vault is enabled for the region (from tfvars, known at plan time)
  # 3. The VM does not have an explicit admin_password
  # 4. The VM does not already have generated_secrets_key_vault_secret_config
  _credential_injection_eligible = {
    for region, vms in local.compute_vms_with_resolved_subnets : region => {
      for vm_key, vm in vms : vm_key =>
        var.compute_auto_credential_keyvault_enabled
        && contains(local._kv_enabled_regions, region)
        && try(vm.admin_password, null) == null
        && try(vm.generated_secrets_key_vault_secret_config, null) == null
    }
  }

  # Inject Key Vault credential config into eligible VMs.
  # Uses explicit field overrides to avoid Terraform's conditional type mismatch.
  compute_vms_with_credentials = {
    for region, vms in local.compute_vms_with_resolved_subnets : region => {
      for vm_key, vm in vms : vm_key => merge(vm, {
        generate_admin_password_or_ssh_key = try(local._credential_injection_eligible[region][vm_key], false) ? true : try(vm.generate_admin_password_or_ssh_key, null)
        generated_secrets_key_vault_secret_config = try(local._credential_injection_eligible[region][vm_key], false) ? {
          key_vault_resource_id = local.regional_kv_resource_ids[region]
        } : try(vm.generated_secrets_key_vault_secret_config, null)
      })
    }
  }
}

# Grant Terraform identity "Key Vault Secrets Officer" on each regional Key Vault
# so the AVM VM module can store generated credentials as secrets.
resource "azurerm_role_assignment" "terraform_kv_secrets_officer" {
  for_each = var.compute_auto_credential_keyvault_enabled && var.compute_enabled ? local.regional_kv_resource_ids : {}

  scope                = each.value
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [module.workload_management]
}

###############################################################################
# Module - Workload VMs
###############################################################################

module "workload_vms" {
  source   = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-workload-vm.git?ref=v1.0.0"
  for_each = var.compute_enabled ? var.compute : {}

  # Subscription
  subscription_id = var.subscription

  # Naming inputs for auto-generation
  workload    = var.naming.workload
  environment = var.naming.env

  # Location - defaults to map key (region name) if not specified
  location = coalesce(each.value.location, each.key)

  # Tags - merge stack tags with region-specific tags
  tags = merge(var.tags, each.value.tags)

  # Disable tag filtering to ensure all tags (including mandatory tags) are passed through
  # The module defaults to filtering to only specific keys, which excludes mandatory policy tags
  tag_keys_to_include = []

  # Log Analytics for diagnostics
  log_analytics_workspace_id = each.value.log_analytics_workspace_id

  # VM Resource Groups
  vm_resource_groups = each.value.vm_resource_groups

  # Virtual Machines with resolved subnet IDs and Key Vault credential config
  vms = local.compute_vms_with_credentials[each.key]

  # Backup Defaults
  backup_defaults = each.value.backup_defaults

  # Security Defaults - Gen2, modern standards
  secure_boot_enabled_default = true
  vtpm_enabled_default        = true

  # Patching Defaults
  enable_automatic_updates_default = true
  patch_mode_default               = "AutomaticByPlatform"

  # ASR/BCDR Configuration - enables Site Recovery replication to target region
  asr_config = each.value.asr_config

  # Depends on vending (subnets), management (Key Vault), and RBAC (secrets officer)
  depends_on = [
    module.subscription_vending,
    module.workload_management,
    azurerm_role_assignment.terraform_kv_secrets_officer,
  ]
}
