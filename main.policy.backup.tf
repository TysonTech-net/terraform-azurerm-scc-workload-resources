###############################################################################
# Subscription-level VM Backup Policy Assignments (Tag-Based Policy Selection)
###############################################################################
# One Azure Policy assignment per (region, backup policy name) combination.
# Each assignment targets VMs tagged with `<backup_policy_tag_name> = <policy_name>`
# and registers them for backup against that policy in the existing
# Terraform-managed Recovery Services Vault.
#
# Tag value matches the policy name EXACTLY. This makes the model trivial
# for customers with N policies per region (no tier abstraction to maintain).
# When policy names are CAF-style with region abbreviations (e.g.
# pol-rsv-identity-prod-basic-uks-001), VMs in different regions get
# region-specific tag values that name the exact target policy.
#
# This replaces the single root-MG `Deploy-VM-Backup` assignment (ALZ library
# ID 98d0b9f8) which created throwaway vaults per RG and offered no per-VM
# retention control. Operators can now change a VM's retention by updating
# its BackupPolicy tag — no Terraform change needed, the policy remediation
# will re-register the VM against the new policy on next evaluation.
#
# Uses built-in Azure policies:
#   - Tier-specific (with tag): 345fa903-145c-4fe1-8bcd-93ec2adccde8
#     "Configure backup on virtual machines with a given tag to an existing
#      recovery services vault in the same location"
#   - Fallback (without tag):   09ce66bc-1220-4153-8104-e3f51c936913
#     "Configure backup on virtual machines without a given tag to an existing
#      recovery services vault in the same location"
#
# Managed Identity: Each assignment's SystemAssigned identity is granted:
#   - Virtual Machine Contributor (9980e02c...) — install backup extension,
#     perform restores
#   - Backup Contributor (5e467623...) — register VMs as protected items
# Both scoped to the subscription.
###############################################################################

locals {
  # Effective per-region backup policy name list. Three modes:
  #
  #   1. var.backup_policy_names is set (customer override) — use as-is.
  #      Each policy name must exist in the vault.
  #
  #   2. var.backup_policy_names is null AND deploy_scc_default_backup_policies
  #      is true — derive from local.scc_default_backup_policy_names which is
  #      built from the merged policies (SCC defaults + user overrides).
  #
  #   3. var.backup_policy_names is null AND deploy_scc_default_backup_policies
  #      is false — empty map, no backup policy assignments are created.
  _effective_backup_policy_names = coalesce(
    var.backup_policy_names,
    local.scc_default_backup_policy_names
  )

  # Cartesian product of (region, policy_name) for tier-specific assignments.
  # Only includes regions where a backup vault is deployed.
  vm_backup_assignments = merge([
    for region, mgmt in var.management : {
      for policy_name in try(local._effective_backup_policy_names[region], []) :
      "${region}_${policy_name}" => {
        region      = region
        location    = mgmt.location
        policy_name = policy_name
      }
      if mgmt.deploy_management_backup_recovery_services_vault
    }
  ]...)

  # Per-region fallback policy name. Uses customer override if supplied,
  # otherwise the first SCC tier (basic) for that region. Skips regions
  # where neither is available (no SCC defaults + no override).
  _effective_fallback_name_per_region = {
    for region, mgmt in var.management : region => (
      try(var.backup_policy_fallback_name_per_region[region], null) != null
      ? var.backup_policy_fallback_name_per_region[region]
      : try(local.scc_default_backup_tiers[region].basic.name, null)
    )
    if mgmt.deploy_management_backup_recovery_services_vault
  }

  # Fallback assignment list: regions with both a vault AND a resolvable
  # fallback policy name. Each gets one fallback subscription policy assignment.
  vm_backup_fallback_assignments = {
    for region, mgmt in var.management : region => {
      region               = region
      location             = mgmt.location
      fallback_policy_name = local._effective_fallback_name_per_region[region]
    }
    if mgmt.deploy_management_backup_recovery_services_vault
    && try(local._effective_fallback_name_per_region[region], null) != null
  }
}

###############################################################################
# Tier-Specific Backup Assignments (inclusion tag)
###############################################################################
# One assignment per (region × policy). VMs tagged
# `<backup_policy_tag_name> = <policy-name>` get registered against that policy.
###############################################################################

resource "azurerm_subscription_policy_assignment" "vm_backup" {
  for_each = local.vm_backup_assignments

  # Assignment name (≤24 chars). Format: "vm-bkp-<short-policy-hash>".
  # Policy names can be long (40+ chars with CAF), so we hash to fit. Using
  # md5 truncated to 16 chars gives ~2^64 unique values per region — collision
  # risk is effectively zero. Prefix gives the assignment a recognisable
  # purpose in compliance views; description gives the full policy name.
  name                 = "vm-bkp-${substr(md5("${each.value.region}-${each.value.policy_name}"), 0, 16)}"
  subscription_id      = "/subscriptions/${var.subscription}"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/345fa903-145c-4fe1-8bcd-93ec2adccde8"
  location             = each.value.location
  display_name         = "Configure VM backup to ${each.value.policy_name} (${each.value.location})"
  description          = "Backs up VMs tagged ${var.backup_policy_tag_name}=${each.value.policy_name} in ${each.value.location} to the ${each.value.policy_name} backup policy in the existing Recovery Services Vault."

  parameters = jsonencode({
    # Required: VMs in this region are backed up to a vault in the same region.
    vaultLocation = {
      value = each.value.location
    }
    # Tag-based inclusion: only VMs whose tag matches this policy name exactly
    # are registered by this assignment. Tag value = policy name (no abstraction).
    inclusionTagName = {
      value = var.backup_policy_tag_name
    }
    inclusionTagValue = {
      value = [each.value.policy_name]
    }
    # Full resource path to the VM backup policy in the vault. Constructed from
    # known inputs (subscription, RG, vault name) rather than module outputs to
    # keep the value plan-time-known.
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
# Safety net for VMs without a valid backup policy tag. Registers them
# against the per-region fallback policy (default: SCC basic tier). Excludes
# VMs with ANY known policy name as their tag value, so they fall through
# only when the tag is missing or has an unrecognised value.
###############################################################################

resource "azurerm_subscription_policy_assignment" "vm_backup_fallback" {
  for_each = local.vm_backup_fallback_assignments

  name                 = "vm-bkp-fallback-${substr(each.value.region, 0, 7)}"
  subscription_id      = "/subscriptions/${var.subscription}"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/09ce66bc-1220-4153-8104-e3f51c936913"
  location             = each.value.location
  display_name         = "Configure VM backup fallback to ${each.value.fallback_policy_name} (${each.value.location})"
  description          = "Registers VMs in ${each.value.location} without a valid ${var.backup_policy_tag_name} tag against ${each.value.fallback_policy_name}. Tier-specific assignments handle VMs tagged with a valid policy name. This is the safety net for untagged VMs."

  parameters = jsonencode({
    vaultLocation = {
      value = each.value.location
    }
    # Exclude VMs tagged with any valid backup policy name (any value in the
    # region's policy list). Anything else (no tag or invalid tag value) falls
    # through to this fallback assignment.
    exclusionTagName = {
      value = var.backup_policy_tag_name
    }
    exclusionTagValue = {
      value = try(local._effective_backup_policy_names[each.value.region], [])
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
# Role IDs sourced from the built-in policies' roleDefinitionIds in the Azure
# Policy GitHub repo (policyDefinitions/Backup/VirtualMachine*_DINE.json).
###############################################################################

# Combined set of all backup policy assignments needing role assignments.
# Keyed predictably so role assignment keys are stable across plans.
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
