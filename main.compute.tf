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
  # Per-VM kill-switch filter (`vm.enabled = false` parks the VM without
  # commenting out its tfvars block). Filtering at this upstream local means
  # every downstream consumer (compute_vms_with_credentials, sub-level policy
  # assignments, the workload-vm module call) naturally skips disabled VMs.
  # Default is `true` — existing tfvars continue to work without modification.
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

        # AUM safety check bypass — required for VMs targeted by Azure Update
        # Manager schedules (which is every TF-managed VM via the MaintenanceWindow
        # tag + dynamic scope). Without this, the VM gets the AUM error:
        #   "This machine has a schedule associated to it. Please select the
        #    required patch orchestration option for the schedule to continue
        #    patching your machine."
        #
        # Setting bypass_platform_safety_checks_on_user_schedule_enabled = true
        # tells Azure to allow the VM to be patched on the customer-managed
        # AUM schedule (rather than the platform-default schedule). Pairs with
        # patch_mode = "AutomaticByPlatform" (already the SCC default in the
        # VM object schema, except for VMs that explicitly opt out via
        # patch_mode = "ImageDefault" — e.g. Tenable marketplace images).
        #
        # Per-VM override is supported: set bypass_platform_safety_checks_on_user_schedule_enabled
        # explicitly to override. Default logic: enable bypass IF patch_mode is
        # AutomaticByPlatform (the AUM-compatible mode). Skip bypass if the VM
        # uses ImageDefault or another non-AUM mode (e.g. Tenable marketplace
        # images that don't support AutomaticByPlatform).
        #
        # Note: explicit null-check rather than try() because the field is declared
        # as optional(bool) on the var.compute schema — when unset, it's null,
        # which try() returns as-is rather than falling through to the fallback.
        # We need the fallback to fire for the common case where the field is
        # not explicitly set.
        bypass_platform_safety_checks_on_user_schedule_enabled = (
          try(vm.bypass_platform_safety_checks_on_user_schedule_enabled, null) != null
          ? vm.bypass_platform_safety_checks_on_user_schedule_enabled
          : try(vm.patch_mode, "AutomaticByPlatform") == "AutomaticByPlatform"
        )

        # Inject operational tags. Three categories are merged into vm.tags:
        #
        #   1. Maintenance window (conditional) — set only when vm.maintenance_window
        #      is specified. Drives Azure Update Manager dynamic scope assignment.
        #      Tag name is configurable via var.maintenance_window_tag_name
        #      (default "MaintenanceWindow"). Pairs with maintenance configs in
        #      alz-mgmt (.scc-maintenance.auto.tfvars).
        #
        #   2. SCC Logic Monitor flags (always) — sccosmanagement,
        #      sccnetworkmanagement. Default to "true"/"false" respectively
        #      (set in the vm object type). Terraform-managed VMs are SCC-managed
        #      by default. Paired with the Enf-VM-Tag-* Audit assignments in
        #      alz-mgmt which validate values are "true" or "false".
        #
        #   3. Backup policy (conditional) — set only when vm.backup_policy is
        #      specified. Tag value is the EXACT policy name as it exists in
        #      the vault (e.g. "pol-rsv-identity-prod-basic-uks-001"). Drives
        #      subscription-level backup policy assignments — VMs without the
        #      tag fall through to the per-region fallback assignment. Tag
        #      name is configurable via var.backup_policy_tag_name (default
        #      "BackupPolicy").
        #
        # Merge order matters: later values override earlier ones. vm.tags
        # (user-supplied) comes first so explicit user tags take precedence
        # over defaults, then operational tags.
        tags = merge(
          coalesce(vm.tags, {}),
          try(vm.maintenance_window, null) != null ? {
            (var.maintenance_window_tag_name) = vm.maintenance_window
          } : {},
          {
            sccosmanagement      = vm.sccosmanagement
            sccnetworkmanagement = vm.sccnetworkmanagement
          },
          try(vm.backup_policy, null) != null ? {
            (var.backup_policy_tag_name) = vm.backup_policy
          } : {}
        )

        # Inject AMA User Assigned Managed Identity into every VM so TF
        # declares what the Azure Policy also assigns. Without this, TF
        # sees SystemAssigned in config but SystemAssigned+UserAssigned
        # in Azure (policy-applied), causing an identity update on every
        # apply that the policy immediately reverts. This aligns them.
        managed_identities = {
          system_assigned = try(vm.managed_identities.system_assigned, true)
          user_assigned_resource_ids = toset(concat(
            tolist(try(vm.managed_identities.user_assigned_resource_ids, [])),
            local.scc_ama_user_assigned_managed_identity_id != null ? [local.scc_ama_user_assigned_managed_identity_id] : []
          ))
        }

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
      }) if try(vm.enabled, true)
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

  # Map of region -> Key Vault resource ID.
  #
  # Constructed as a plan-time-known string from var.subscription, the management
  # resource group name, and the Key Vault name rather than referencing the
  # module output. This avoids an "Invalid count argument" error in the AVM VM
  # module's azurerm_key_vault_secret resources, whose `count` depends on
  # whether `generated_secrets_key_vault_secret_config` is non-null. The module
  # output is unknown on first plan (the vault doesn't exist yet), which makes
  # the non-null check indeterminate. Constructing the ID from inputs keeps it
  # known at plan time; at apply time the value resolves to the same real
  # resource so no drift is introduced.
  #
  # The KV name matches the construction in main.management.tf line 67:
  # coalesce(each.value.management_kv_name, "{kv_base}{random4}{instance}").
  # When management_kv_name is explicit, that wins. Otherwise we use the same
  # naming logic (which depends on random_string.key_vault_suffix — stable
  # across plans once created).
  regional_kv_resource_ids = {
    for region in local._kv_enabled_regions :
    region => format(
      "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.KeyVault/vaults/%s",
      var.subscription,
      var.management[region].management_resource_group_name,
      coalesce(
        var.management[region].management_kv_name,
        "${local.naming.key_vault_base[var.management[region].location]}${random_string.key_vault_suffix[region].result}${var.naming.instance}"
      )
    )
  }

  # Resolve effective admin_password per VM:
  # Priority: explicit admin_password in tfvars > var.vm_admin_password fallback > null (auto-generate)
  _effective_admin_password = {
    for region, vms in local.compute_vms_with_resolved_subnets : region => {
      for vm_key, vm in vms : vm_key => try(vm.admin_password, null) != null ? vm.admin_password : var.vm_admin_password
    }
  }

  # VMs eligible for auto-generated credentials (no password available at all).
  # Applies to both Windows and Linux — the AVM VM module handles OS-specific
  # generation (random password for Windows, tls_private_key SSH key for Linux)
  # and stores both in the Key Vault via `generated_secrets_key_vault_secret_config`.
  # The plan-time count ambiguity that previously affected Linux VMs is resolved
  # by constructing regional_kv_resource_ids as a plan-time-known string above.
  _credential_autogen_eligible = {
    for region, vms in local.compute_vms_with_resolved_subnets : region => {
      for vm_key, vm in vms : vm_key =>
      var.compute_auto_credential_keyvault_enabled
      && contains(local._kv_enabled_regions, region)
      && local._effective_admin_password[region][vm_key] == null
      && try(vm.generated_secrets_key_vault_secret_config, null) == null
    }
  }

  # VMs eligible for storing their password in Key Vault (have a password + KV enabled).
  #
  # Implicit default: any VM with an effective admin_password (explicit or via
  # var.vm_admin_password env-injected fallback) automatically gets the password
  # stored in the regional Key Vault when KV is deployed. This keeps credentials
  # retrievable for operational access without requiring each VM to opt in.
  #
  # The `store_password_in_keyvault` flag remains supported for explicit override
  # but defaults to `true` when unset — consumers must explicitly set it to
  # `false` to suppress KV storage for a specific VM (e.g. ephemeral dev VMs
  # where credential retrieval isn't needed).
  _credential_store_eligible = {
    for region, vms in local.compute_vms_with_resolved_subnets : region => {
      for vm_key, vm in vms : vm_key =>
      var.compute_auto_credential_keyvault_enabled
      && contains(local._kv_enabled_regions, region)
      && local._effective_admin_password[region][vm_key] != null
      && try(vm.store_password_in_keyvault, true) == true
    }
  }

  # Inject credentials into VMs. Three modes:
  #   1. Auto-generate: no password anywhere, generates random + stores in KV
  #   2. Fallback: vm_admin_password set via env var, used as password + stores in KV
  #   3. Store explicit: admin_password in tfvars + store_password_in_keyvault, stores in KV
  compute_vms_with_credentials = {
    for region, vms in local.compute_vms_with_resolved_subnets : region => {
      for vm_key, vm in vms : vm_key => merge(vm, {
        admin_password                     = local._effective_admin_password[region][vm_key]
        generate_admin_password_or_ssh_key = try(local._credential_autogen_eligible[region][vm_key], false) ? true : try(vm.generate_admin_password_or_ssh_key, null)
        generated_secrets_key_vault_secret_config = (
          try(local._credential_autogen_eligible[region][vm_key], false)
          || try(local._credential_store_eligible[region][vm_key], false)
          ) ? {
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
  source   = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-workload-vm.git?ref=v1.3.3"
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
  # Injects the central Automation Account ID from platform_shared state for
  # ASR agent auto-update, unless explicitly overridden in the compute tfvars.
  # Cannot use merge() here as it loses the typed object structure required by
  # the downstream variable. Instead, pass through as-is and let the module
  # default automation_account_id from the asr_config input. The ID is injected
  # via a local that resolves the effective asr_config per region.
  asr_config = each.value.asr_config != null ? {
    target_location                              = each.value.asr_config.target_location
    infrastructure_enabled                       = try(each.value.asr_config.infrastructure_enabled, true)
    use_existing_vault                           = try(each.value.asr_config.use_existing_vault, false)
    vault_name                                   = try(each.value.asr_config.vault_name, null)
    vault_resource_group_name                    = try(each.value.asr_config.vault_resource_group_name, null)
    vault_resource_group_key                     = try(each.value.asr_config.vault_resource_group_key, null)
    recovery_point_retention_in_minutes          = try(each.value.asr_config.recovery_point_retention_in_minutes, 1440)
    app_consistent_snapshot_frequency_in_minutes = try(each.value.asr_config.app_consistent_snapshot_frequency_in_minutes, 240)
    target_network_id                            = try(each.value.asr_config.target_network_id, null)
    target_network_name                          = try(each.value.asr_config.target_network_name, null)
    target_network_resource_group                = try(each.value.asr_config.target_network_resource_group, null)
    target_subnet_name                           = try(each.value.asr_config.target_subnet_name, null)
    target_resource_group_id                     = try(each.value.asr_config.target_resource_group_id, null)
    target_resource_group_name                   = try(each.value.asr_config.target_resource_group_name, null)
    target_resource_group_key                    = try(each.value.asr_config.target_resource_group_key, null)
    enable_capacity_reservation                  = try(each.value.asr_config.enable_capacity_reservation, false)
    capacity_reservation_sku                     = try(each.value.asr_config.capacity_reservation_sku, null)
    create_test_network                          = try(each.value.asr_config.create_test_network, false)
    test_network_address_space                   = try(each.value.asr_config.test_network_address_space, [])
    test_network_subnet_newbits                  = try(each.value.asr_config.test_network_subnet_newbits, 4)
    # Automation Account for ASR agent auto-update. Must be in the same
    # subscription as the ASR vault. Resolved from the workload_management
    # module output for the target region (where the vault lives).
    # Falls back to explicit tfvars override if provided.
    # Automation Account for ASR agent auto-update. Resolved from:
    # 1. Explicit override in compute tfvars (asr_config.automation_account_id)
    # 2. Workload management module output for the target region
    # 3. null (auto-update disabled, agents stay on installed version)
    automation_account_id = try(
      coalesce(
        try(each.value.asr_config.automation_account_id, null),
        try(module.workload_management[each.value.asr_config.target_location].management_automation_account_resource_id, null)
      ),
      null
    )
  } : null

  # Depends on vending (subnets), management (Key Vault), and RBAC (secrets officer)
  depends_on = [
    module.subscription_vending,
    module.workload_management,
    azurerm_role_assignment.terraform_kv_secrets_officer,
  ]
}
