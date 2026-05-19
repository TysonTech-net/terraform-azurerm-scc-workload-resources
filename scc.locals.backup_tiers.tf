###############################################################################
# SCC Standard VM Backup Policy Definitions (Constant-Named)
###############################################################################
# Defines three SCC-standard VM backup policy definitions with constant names
# that are the SAME across all vaults, regions, and workloads:
#
#   SCC-BasicBackup     : 30 days daily
#   SCC-StandardBackup  : 14 daily + 4 weekly + 3 monthly
#   SCC-ExtendedBackup  : 14 daily + 4 weekly + 12 monthly + 7 yearly
#
# Constant naming (rather than CAF naming with workload/region embedded) lets
# VMs across all platforms use the same BackupPolicy tag value to select a
# given tier, and lets the alz-mgmt root-MG Modify/Audit policies enumerate
# valid values without per-workload/region knowledge.
#
# These definitions are merged into management_backup_rsv_vm_backup_policy
# (passed to scc-workload-management) so they get deployed into each region's
# Recovery Services Vault. The same names are then referenced by the
# subscription-level backup policy assignments in main.policy.backup.tf —
# VMs tagged with `BackupPolicy = <exact-policy-name>` are registered against
# that policy in the vault.
#
# Customer-supplied additional policies (via var.management[region].management_backup_rsv_vm_backup_policy)
# can use any naming convention (CAF or otherwise). Only the SCC-shipped
# defaults follow the constant naming.
#
# Toggle `var.deploy_scc_default_backup_policies` (default: true) controls
# whether these SCC defaults are deployed. Customers with their own backup
# policies should set this to false and supply their own policies via
# var.management[region].management_backup_rsv_vm_backup_policy + override
# var.backup_policy_names with their policy name list per region.
#
# All three SCC tiers share:
#   - Daily frequency at 23:00 UTC (out of business hours)
#   - 5-day instant restore retention (snapshot-based quick recovery)
#   - Policy type V2 (enhanced, supports hourly backups if needed)
#
# Retention varies per tier:
#   - basic    : 30 days daily (dev/test, short-term recovery)
#   - standard : 14 daily + 4 weekly + 3 monthly (default production)
#   - extended : 14 daily + 4 weekly + 12 monthly + 7 yearly (regulatory)
###############################################################################

locals {
  # Per-region SCC tier definitions with CAF-auto-generated names.
  # Structured as map(region => map(internal_tier_key => tier_definition)).
  # The internal tier key (basic/standard/extended) is just for indexing within
  # the locals — the customer-facing identifier is the .name field which is
  # what VMs tag themselves with.
  _scc_default_backup_tiers_all = {
    for region, abbr in local.get_region_abbr : region => {
      # Constant SCC tier names — same across all vaults, regions, and workloads.
      # VMs everywhere can use the same BackupPolicy tag value to select a tier,
      # which keeps the alz-mgmt root-MG Modify/Audit policies simple (no need
      # to know per-workload/region context to enumerate valid values).
      #
      # Customer-supplied additional policies (via
      # var.management[region].management_backup_rsv_vm_backup_policy) can use
      # any naming convention they want — only the SCC-shipped policies follow
      # the constant naming.
      basic = {
        name                           = "SCC-BasicBackup"
        timezone                       = "UTC"
        instant_restore_retention_days = 5
        policy_type                    = "V2"
        frequency                      = "Daily"
        retention_daily                = 30
        backup = {
          time = "23:00"
        }
      }
      standard = {
        name                           = "SCC-StandardBackup"
        timezone                       = "UTC"
        instant_restore_retention_days = 5
        policy_type                    = "V2"
        frequency                      = "Daily"
        retention_daily                = 14
        backup = {
          time = "23:00"
        }
        retention_weekly = {
          count    = 4
          weekdays = ["Sunday"]
        }
        retention_monthly = {
          count    = 3
          weekdays = ["Sunday"]
          weeks    = ["First"]
        }
      }
      extended = {
        name                           = "SCC-ExtendedBackup"
        timezone                       = "UTC"
        instant_restore_retention_days = 5
        policy_type                    = "V2"
        frequency                      = "Daily"
        retention_daily                = 14
        backup = {
          time = "23:00"
        }
        retention_weekly = {
          count    = 4
          weekdays = ["Sunday"]
        }
        retention_monthly = {
          count    = 12
          weekdays = ["Sunday"]
          weeks    = ["First"]
        }
        retention_yearly = {
          count    = 7
          months   = ["January"]
          weekdays = ["Sunday"]
          weeks    = ["First"]
        }
      }
    }
  }

  # Per-region SCC tier definitions, gated by the toggle.
  # Filtered via for-expression to avoid Terraform's "inconsistent conditional
  # result types" error that a ternary branching on {} would trigger.
  scc_default_backup_tiers = {
    for region, tiers in local._scc_default_backup_tiers_all :
    region => tiers if var.deploy_scc_default_backup_policies
  }

  # Merged backup policies per region: SCC defaults + user-supplied policies.
  # User-supplied keys (from var.management[region].management_backup_rsv_vm_backup_policy)
  # override SCC defaults on collision. The merged map is what gets passed to
  # scc-workload-management for actual deployment into the vault.
  merged_vm_backup_policies = {
    for region, mgmt in var.management :
    region => merge(
      try(local.scc_default_backup_tiers[region], {}),
      coalesce(mgmt.management_backup_rsv_vm_backup_policy, {})
    )
  }

  # Per-region list of all backup policy NAMES that exist in the vault.
  # Derived from merged_vm_backup_policies (.name field of each definition).
  # This is the list the subscription-level policy assignments iterate over
  # to create one assignment per (region, policy_name) — VMs tagged
  # `BackupPolicy = <name>` get registered against the matching policy.
  scc_default_backup_policy_names = {
    for region, policies in local.merged_vm_backup_policies :
    region => [for k, p in policies : p.name]
  }
}
