###############################################################################
# Subscription-level VM Backup Policy Assignments (Tag-Based Tier Selection)
###############################################################################
# One Azure Policy assignment per SCC backup tier. Each assignment targets
# VMs tagged with `BackupPolicy = <tier>` and registers them for backup
# against the matching policy in the existing Terraform-managed Recovery
# Services Vault.
#
# This replaces the single root-MG `Deploy-VM-Backup` assignment (ALZ library
# ID 98d0b9f8) which created throwaway vaults per RG and offered no per-VM
# retention control. Operators can now change a VM's retention by updating
# its `BackupPolicy` tag — no Terraform change needed on apply, the policy
# remediation will re-register the VM against the new tier.
#
# Uses built-in Azure policy:
#   Name: Configure backup on virtual machines with a given tag to an
#         existing recovery services vault in the same location
#   ID:   345fa903-145c-4fe1-8bcd-93ec2adccde8
#   Variant: "existing vault, with tag" — only backs up VMs tagged to match.
#            Pairs with Azure Policy Modify on `BackupPolicy` in alz-mgmt
#            which defaults the tag to SCC-BasicRetention when missing.
#
# Scope: Cartesian product of (region with backup vault) x (SCC backup tier).
# For a dual-region deployment with all three tiers enabled: 6 assignments.
# Names are bounded to 24 characters (Azure limit) via substr() on the tier key.
#
# Managed Identity: Each assignment's SystemAssigned identity is granted:
#   - Virtual Machine Contributor (9980e02c...) — install backup extension,
#     perform restores
#   - Backup Contributor (5e467623...) — register VMs as protected items
# Both scoped to the subscription.
###############################################################################

locals {
  # Effective backup policy tiers. Three modes:
  #
  #   1. var.backup_policy_tiers is set (customer override) — use as-is.
  #      Each tier's policy_name_per_region (or single policy_name) must
  #      match a policy that exists in the vault. Tier keys become the
  #      valid BackupPolicy tag values.
  #
  #   2. var.backup_policy_tiers is null AND deploy_scc_default_backup_policies
  #      is true — derive tiers from SCC CAF-named defaults (scc.locals.backup_tiers.tf).
  #      Policy names are auto-generated per region following the CAF pattern
  #      pol-rsv-<workload>-<env>-<tier>-<region>-<instance>.
  #
  #   3. var.backup_policy_tiers is null AND deploy_scc_default_backup_policies
  #      is false — empty map, no backup policy assignments are created.
  #      Consumers using this combination should deploy their own backup
  #      policy assignments separately (or use mode 1 above).
  # Auto-derived SCC tier map (used when var.backup_policy_tiers is null
  # and SCC defaults are enabled). Unconditional definition avoids the
  # "inconsistent conditional result types" error that a ternary branching
  # on {} would trigger — we filter below instead.
  _scc_tiers_auto = {
    basic = {
      policy_name_per_region = { for region, names in local.scc_tier_policy_names : region => names.basic }
      description            = "SCC-BasicRetention: 30 days daily. Dev/test workloads."
    }
    standard = {
      policy_name_per_region = { for region, names in local.scc_tier_policy_names : region => names.standard }
      description            = "SCC-StandardRetention: 14 daily + 4 weekly + 3 monthly. Default production."
    }
    extended = {
      policy_name_per_region = { for region, names in local.scc_tier_policy_names : region => names.extended }
      description            = "SCC-ExtendedRetention: 14 daily + 4 weekly + 12 monthly + 7 yearly. Compliance workloads."
    }
  }

  # SCC defaults, gated by the toggle. When disabled, empty map.
  _scc_tiers_enabled = {
    for k, v in local._scc_tiers_auto : k => v
    if var.deploy_scc_default_backup_policies
  }

  # Effective tiers: prefer explicit var.backup_policy_tiers override (customer
  # supplied) over SCC auto-derived tiers. When both are null/empty, no backup
  # policy assignments are created.
  _effective_backup_tiers = coalesce(
    var.backup_policy_tiers,
    local._scc_tiers_enabled
  )

  # Helper to resolve a tier's policy name for a given region. Prefers
  # policy_name_per_region (explicit per-region mapping) over policy_name
  # (single name used everywhere). Returns null if neither set.
  _tier_policy_name_for_region = {
    for tier_key, tier in local._effective_backup_tiers : tier_key => {
      for region, mgmt in var.management : region => (
        try(tier.policy_name_per_region[region], null) != null
        ? tier.policy_name_per_region[region]
        : tier.policy_name
      )
    }
  }

  # Cartesian product of region x tier for subscription policy assignments.
  # Only includes regions where a backup vault is deployed AND the tier has
  # a resolvable policy name for that region.
  vm_backup_assignments = merge([
    for region, mgmt in var.management : {
      for tier_key, tier in local._effective_backup_tiers :
      "${region}_${tier_key}" => {
        region      = region
        location    = mgmt.location
        tier_key    = tier_key
        policy_name = local._tier_policy_name_for_region[tier_key][region]
        description = try(tier.description, "")
      }
      if mgmt.deploy_management_backup_recovery_services_vault
      && local._tier_policy_name_for_region[tier_key][region] != null
    }
  ]...)
}

###############################################################################
# Tier-Specific Backup Assignments (inclusion tag)
###############################################################################
# One assignment per (region × tier). VMs tagged BackupPolicy=<tier-name>
# get registered against that tier's backup policy.
###############################################################################

resource "azurerm_subscription_policy_assignment" "vm_backup" {
  for_each = local.vm_backup_assignments

  # Assignment name (≤24 chars). Format: "vm-bkp-<region-short>-<tier-short>".
  # substr() bounds defensively if longer keys are introduced.
  name                 = "vm-bkp-${substr(each.value.region, 0, 6)}-${substr(each.value.tier_key, 0, 8)}"
  subscription_id      = "/subscriptions/${var.subscription}"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8"
  location             = each.value.location
  display_name         = "Configure VM backup (${each.value.tier_key} tier, ${each.value.location})"
  description          = "Backs up VMs tagged ${var.backup_policy_tag_name}=${each.value.tier_key} in ${each.value.location} to the ${each.value.policy_name} policy in the existing Recovery Services Vault. ${each.value.description}"

  parameters = jsonencode({
    # Required: VMs in this region are backed up to a vault in the same region.
    vaultLocation = {
      value = each.value.location
    }
    # Tag-based inclusion: only VMs with `<tag_name> = <tier_key>` are
    # registered by this assignment. Tag value is the tier KEY (e.g. "basic")
    # not the policy name — this keeps tag values portable across regions
    # (policy names differ per region via CAF naming). The module translates
    # tag value → region-specific policy name via var.backup_policy_tiers.
    # The Modify policy in alz-mgmt (Add-Tag-VM-BkpPolicy) defaults missing
    # tags to the configured fallback tier key.
    inclusionTagName = {
      value = var.backup_policy_tag_name
    }
    inclusionTagValue = {
      value = [each.value.tier_key]
    }
    # Full resource path to the VM backup policy in the vault. Constructed from
    # known inputs (subscription, RG, vault name) rather than module outputs to
    # keep the value plan-time-known. Vault name comes from var.management — it's
    # required for the backup vault to be deployed, so we can reference it directly.
    backupPolicyId = {
      value = format(
        "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.RecoveryServices/vaults/%s/backupPolicies/%s",
        var.subscription,
        var.management[each.value.region].management_resource_group_name,
        var.management[each.value.region].management_backup_rsv_name,
        each.value.policy_name
      )
    }
    # DeployIfNotExists = auto-register matching VMs at creation. Audit flags
    # non-compliance without registering. Disabled turns the policy off.
    effect = {
      value = "DeployIfNotExists"
    }
  })

  identity {
    type = "SystemAssigned"
  }
}

###############################################################################
# Fallback Backup Assignment (exclusion tag)
###############################################################################
# Safety net for VMs without a BackupPolicy tag. Registers them against the
# default tier (SCC-BasicRetention) to ensure nothing slips through the cracks.
#
# Pairs with the Azure Policy Modify effect in alz-mgmt (Add-Tag-VM-BkpPolicy)
# which defaults the tag to SCC-BasicRetention on VMs created outside Terraform.
# But policy evaluation can lag VM creation by up to 30 minutes, so this
# fallback ensures backup protection from the moment a VM is created, regardless
# of whether the Modify has fired yet.
#
# Uses built-in "without tag" variant 09ce66bc-1220-4153-8104-e3f51c936913.
# Exclusion tag set to BackupPolicy with the three valid tier values — meaning
# ANY VM already tagged with a valid tier is excluded from this fallback and
# handled by its tier-specific assignment above. Untagged VMs (or VMs with an
# invalid tag value) get the Basic tier by default.
###############################################################################

locals {
  # Fallback assignments: one per region with a vault. Uses the tier identified
  # by var.backup_policy_fallback_tier (default "basic") as the backup target.
  # Excludes VMs tagged with ANY valid tier value so they flow to their
  # tier-specific assignment instead.
  #
  # Only created when there's at least one tier defined. If
  # local._effective_backup_tiers is empty (both SCC defaults disabled AND
  # var.backup_policy_tiers null), no fallback is needed either.
  vm_backup_fallback_assignments = length(local._effective_backup_tiers) > 0 ? {
    for region, mgmt in var.management : region => {
      region   = region
      location = mgmt.location
      # Resolve the fallback tier's policy name for this region. Pulls from
      # _tier_policy_name_for_region populated above, using the fallback tier key.
      fallback_policy_name = try(
        local._tier_policy_name_for_region[var.backup_policy_fallback_tier][region],
        null
      )
    }
    if mgmt.deploy_management_backup_recovery_services_vault
    && try(local._tier_policy_name_for_region[var.backup_policy_fallback_tier][region], null) != null
  } : {}

  # All valid tier tag values across all regions — used to build the exclusion
  # list for the fallback assignment. A VM is excluded from fallback if it has
  # the BackupPolicy tag set to ANY known tier key. Anything else (no tag,
  # typo'd tag value) falls through and gets the fallback tier.
  _all_tier_tag_values = keys(local._effective_backup_tiers)
}

resource "azurerm_subscription_policy_assignment" "vm_backup_fallback" {
  for_each = local.vm_backup_fallback_assignments

  name                 = "vm-bkp-fallback-${substr(each.value.region, 0, 7)}"
  subscription_id      = "/subscriptions/${var.subscription}"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/09ce66bc-1220-4153-8104-e3f51c936913"
  location             = each.value.location
  display_name         = "Configure VM backup fallback to ${each.value.fallback_policy_name} (${each.value.location})"
  description          = "Registers VMs in ${each.value.location} without a valid ${var.backup_policy_tag_name} tag against the ${var.backup_policy_fallback_tier} tier (${each.value.fallback_policy_name}). Tier-specific assignments handle VMs tagged with a valid tier value. This assignment is the safety net for untagged VMs."

  parameters = jsonencode({
    vaultLocation = {
      value = each.value.location
    }
    # Exclude VMs tagged with any valid tier — they're handled by the tier-specific
    # assignments above. Anything else (no tag or invalid tag value) falls through
    # to this assignment and gets the fallback tier.
    exclusionTagName = {
      value = var.backup_policy_tag_name
    }
    exclusionTagValue = {
      value = local._all_tier_tag_values
    }
    backupPolicyId = {
      value = format(
        "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.RecoveryServices/vaults/%s/backupPolicies/%s",
        var.subscription,
        var.management[each.value.region].management_resource_group_name,
        var.management[each.value.region].management_backup_rsv_name,
        each.value.fallback_policy_name
      )
    }
    effect = {
      value = "DeployIfNotExists"
    }
  })

  identity {
    type = "SystemAssigned"
  }
}

###############################################################################
# Policy Managed Identity Role Assignments
###############################################################################
# One set of role assignments per policy assignment (subscription-scoped).
# Role IDs sourced from the built-in policy's roleDefinitionIds in the Azure
# Policy GitHub repo (policyDefinitions/Backup/VirtualMachineWithTag_DINE.json).
###############################################################################

# Combined set of all backup policy assignments (tier-specific + fallback)
# needing role assignments. Keyed by the same key the source resource uses
# so role assignment keys are predictable.
locals {
  all_vm_backup_assignment_identities = merge(
    { for k, a in azurerm_subscription_policy_assignment.vm_backup : "tier-${k}" => a.identity[0].principal_id },
    { for k, a in azurerm_subscription_policy_assignment.vm_backup_fallback : "fallback-${k}" => a.identity[0].principal_id }
  )
}

# Virtual Machine Contributor — install backup extension, perform restores.
resource "azurerm_role_assignment" "vm_backup_policy_vm_contributor" {
  for_each = local.all_vm_backup_assignment_identities

  scope                            = "/subscriptions/${var.subscription}"
  role_definition_id               = "/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}

# Backup Contributor — register VMs as protected items in the vault.
resource "azurerm_role_assignment" "vm_backup_policy_backup_contributor" {
  for_each = local.all_vm_backup_assignment_identities

  scope                            = "/subscriptions/${var.subscription}"
  role_definition_id               = "/providers/Microsoft.Authorization/roleDefinitions/5e467623-bb1f-42f4-a55d-6e525e11384b"
  principal_id                     = each.value
  skip_service_principal_aad_check = true
}
