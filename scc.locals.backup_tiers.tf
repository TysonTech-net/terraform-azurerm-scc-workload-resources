###############################################################################
# SCC Standard VM Backup Policy Tiers (CAF-Named)
###############################################################################
# Defines three SCC-standard VM backup policy tiers with auto-generated
# policy names following the CAF (Cloud Adoption Framework) pattern:
#
#   pol-rsv-{workload}-{env}-{tier}-{region_abbr}-{instance}
#
# Examples:
#   pol-rsv-identity-prod-basic-uks-001
#   pol-rsv-security-prod-standard-ukw-001
#   pol-rsv-management-prod-extended-uks-001
#
# These tier definitions are passed to scc-workload-management (via
# management_backup_rsv_vm_backup_policy) for deployment into each region's
# Recovery Services Vault. The tier names are also used by
# main.policy.backup.tf which creates subscription-level Azure Policy
# assignments that register VMs against the matching tier based on their
# `BackupPolicy` tag value.
#
# Toggle `var.deploy_scc_default_backup_policies` (default: true) controls
# whether these SCC defaults are deployed. Customers with their own backup
# policies should set this to false and supply their own tier definitions
# via var.management[region].management_backup_rsv_vm_backup_policy.
#
# All three SCC tiers share:
#   - Daily frequency at 23:00 UTC (out of business hours)
#   - 5-day instant restore retention (snapshot-based quick recovery)
#   - Policy type V2 (enhanced, supports hourly backups if needed)
#
# Retention varies per tier:
#   - Basic    : 30 days daily (dev/test, short-term recovery)
#   - Standard : 14 daily + 4 weekly + 3 monthly (default production)
#   - Extended : 14 daily + 4 weekly + 12 monthly + 7 yearly (regulatory)
#
# The Yearly retention in Extended is an Archive tier candidate — Azure
# Backup supports moving monthly and yearly recovery points older than 3
# months (with 6+ months remaining retention) to Archive storage tier for
# cost savings. This is configured at the vault/policy level post-deploy,
# not in the policy definition itself.
###############################################################################

locals {
  # Full list of SCC-standard tier definitions with CAF-auto-generated names.
  # Structured as map(region => map(tier_key => tier_definition)) because the
  # policy name includes the region abbreviation, and the variable being passed
  # to the child module is per-region (var.management[region]...).
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

  # Per-region SCC defaults, gated by the toggle.
  # Uses a `for` expression with conditional filter to avoid Terraform's
  # "inconsistent conditional result types" error that a ternary would trigger
  # when the true branch is a typed object and the false branch is an empty map.
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

  # Maps tier key -> CAF policy name per region. Used by main.policy.backup.tf
  # to construct subscription-level policy assignments that reference these
  # by the exact name deployed into the vault.
  scc_tier_policy_names = {
    for region, tiers in local.scc_default_backup_tiers :
    region => { for tier_key, tier in tiers : tier_key => tier.name }
  }
}
