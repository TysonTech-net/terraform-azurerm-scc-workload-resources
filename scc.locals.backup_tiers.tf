###############################################################################
# SCC Standard VM Backup Policy Definitions (CAF-Named)
###############################################################################
# Defines three SCC-standard VM backup policy definitions with auto-generated
# names following the CAF (Cloud Adoption Framework) pattern:
#
#   pol-rsv-{workload}-{env}-{tier}-{region_abbr}-{instance}
#
# Examples:
#   pol-rsv-identity-prod-basic-uks-001
#   pol-rsv-security-prod-standard-ukw-001
#   pol-rsv-management-prod-extended-uks-001
#
# These definitions are merged into management_backup_rsv_vm_backup_policy
# (passed to scc-workload-management) so they get deployed into each region's
# Recovery Services Vault. The same names are then referenced by the
# subscription-level backup policy assignments in main.policy.backup.tf —
# VMs tagged with `BackupPolicy = <exact-policy-name>` are registered against
# that policy in the vault.
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
      basic = {
        name                           = "pol-rsv-${var.naming.workload}-${var.naming.env}-basic-${abbr}-${var.naming.instance}"
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
        name                           = "pol-rsv-${var.naming.workload}-${var.naming.env}-standard-${abbr}-${var.naming.instance}"
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
        name                           = "pol-rsv-${var.naming.workload}-${var.naming.env}-extended-${abbr}-${var.naming.instance}"
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
