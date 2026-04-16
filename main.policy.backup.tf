###############################################################################
# Subscription-level VM Backup Policy Assignment
###############################################################################
# Auto-assigns VMs in the workload subscription to the existing Terraform-
# managed Recovery Services Vault deployed by the management module. This
# replaces the root-MG-level `Deploy-VM-Backup` policy assignment (ALZ library
# ID 98d0b9f8-fd90-49c9-88e2-d3baf3b0dd86) which auto-creates a new vault per
# resource group and fragments backup coverage.
#
# Uses the built-in Azure policy:
#   Name: Configure backup on virtual machines without a given tag to an
#         existing recovery services vault in the same location
#   ID:   09ce66bc-1220-4153-8104-e3f51c936913
#   Variant: "existing vault, without tag" — backs up everything by default,
#            optionally excludes VMs with a specified exclusion tag. The "with
#            tag" variants (345fa903/83644c87) are inclusion-based and require
#            tagging each VM to opt in.
#
# Scope: Deployed per region that has a backup vault. Each assignment points
# at its regional vault (uksouth → rsv-backup-<workload>-prod-uks-001, etc).
# Linux and Windows VMs are both covered by the built-in policy's image
# filter (Windows Server, SQL Server, Ubuntu, RHEL, CentOS, Oracle Linux,
# SUSE, etc).
#
# Managed Identity: The policy's SystemAssigned identity is granted two roles
# at the subscription scope:
#   - Virtual Machine Contributor (9980e02c...) — to install the backup
#     extension and perform restore operations on VMs
#   - Backup Contributor (5e467623...) — to register VMs as protected items
#     in the Recovery Services Vault
#
# Default backup policy: SCC-BasicRetention (baked into the vault by
# scc-workload-management v1.1.0+). Override via var.vm_backup_policy_name if
# a different tier is required (e.g. SCC-StandardRetention for production
# workloads with mid-term retention requirements).
#
# Remediation: After apply, create a remediation task in the Azure Portal
# (Policy → Remediation) to backfill backup registration on existing VMs
# that were deployed before this assignment was in place. New VMs are
# automatically protected within minutes of creation.
###############################################################################

resource "azurerm_subscription_policy_assignment" "vm_backup" {
  # One assignment per region that has a backup vault deployed. The filter
  # uses `deploy_management_backup_recovery_services_vault` from var.management
  # (known at plan time) rather than inspecting the module output (unknown
  # on first plan, same reason as the credential autogen pattern in main.compute.tf).
  for_each = {
    for key, mgmt in var.management : key => mgmt
    if mgmt.deploy_management_backup_recovery_services_vault
  }

  # Name must be ≤24 chars. Format: "deploy-vm-bkp-<region-key>".
  # Region keys are typically short (e.g. "uksouth", "ukwest") so this fits.
  # substr bounds the name defensively if a longer key is ever introduced.
  name                 = "deploy-vm-bkp-${substr(each.key, 0, 10)}"
  subscription_id      = "/subscriptions/${var.subscription}"
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/09ce66bc-1220-4153-8104-e3f51c936913"
  location             = each.value.location
  display_name         = "Configure VM backup to existing vault (${each.value.location})"
  description          = "Backs up all VMs in this subscription to the existing Recovery Services Vault in ${each.value.location}. Uses the ${var.vm_backup_policy_name} backup policy tier."

  parameters = jsonencode({
    # Required by the built-in policy: VMs in this region are backed up to
    # a vault in the same region (backups can't cross regions).
    vaultLocation = {
      value = each.value.location
    }
    # Full resource path to the VM backup policy in the vault. Constructed from
    # the module output (known after apply) and the configured policy name.
    # The vault resource ID is stable, so referencing it here doesn't introduce
    # plan-time unknowns (the assignment itself depends on the vault existing).
    backupPolicyId = {
      value = "${module.workload_management[each.key].management_backup_rsv_resource_id[0]}/backupPolicies/${var.vm_backup_policy_name}"
    }
    # Empty exclusion tag = back up everything. Consumers can override via
    # policy_assignments_to_modify in tfvars to exclude specific VMs (e.g.
    # ephemeral scratch VMs, VMs with custom backup arrangements).
    exclusionTagName = {
      value = ""
    }
    exclusionTagValue = {
      value = []
    }
    # DeployIfNotExists = auto-register new VMs at creation time. Audit would
    # flag non-compliance but not register. Disabled turns the policy off
    # entirely (use `enforcement_mode` instead if you want tag history retained).
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
# The built-in policy's DeployIfNotExists effect runs a deployment that both
# (a) modifies the VM to install the backup extension, and
# (b) registers the VM as a protected item in the vault.
# Both require specific roles at the subscription scope. The AVM ALZ module
# handles this automatically for root-MG policies, but subscription-level
# assignments created outside that module need explicit role assignments.
#
# Role IDs sourced from the built-in policy's roleDefinitionIds in the Azure
# Policy GitHub repo (policyDefinitions/Backup/VirtualMachineBackup_DINE.json).
###############################################################################

# Virtual Machine Contributor — needed to install the backup extension on VMs
# and to initiate restore operations. Broader than strictly necessary for
# backup registration alone, but matches the built-in policy's requirements.
resource "azurerm_role_assignment" "vm_backup_policy_vm_contributor" {
  for_each = azurerm_subscription_policy_assignment.vm_backup

  scope                            = "/subscriptions/${var.subscription}"
  role_definition_id               = "/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
  principal_id                     = each.value.identity[0].principal_id
  skip_service_principal_aad_check = true
}

# Backup Contributor — needed to register VMs as protected items in the vault
# and to configure the backup policy association. Scoped to the subscription
# rather than the vault RG so the identity can operate across all vaults that
# might be in the subscription (though typically one per region).
resource "azurerm_role_assignment" "vm_backup_policy_backup_contributor" {
  for_each = azurerm_subscription_policy_assignment.vm_backup

  scope                            = "/subscriptions/${var.subscription}"
  role_definition_id               = "/providers/Microsoft.Authorization/roleDefinitions/5e467623-bb1f-42f4-a55d-6e525e11384b"
  principal_id                     = each.value.identity[0].principal_id
  skip_service_principal_aad_check = true
}
