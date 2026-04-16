###############################################################################
# SCC Backup Policy + Operational Tag Variables
###############################################################################
# Controls the SCC standard backup tier definitions (defined in
# scc.locals.backup_tiers.tf) and the tag names used for operational
# tagging + policy scoping.
#
# All default to SCC conventions; override for customer-specific deployments
# with different retention requirements, naming conventions, or tag schemes.
###############################################################################

variable "deploy_scc_default_backup_policies" {
  type        = bool
  default     = true
  description = <<-DESCRIPTION
Deploy SCC standard VM backup policy definitions (basic, standard, extended)
into each deployed Recovery Services Vault. Names are auto-generated from the
CAF pattern: pol-rsv-<workload>-<env>-<tier>-<region>-<instance>.

Defaults to true. Set false if your deployment uses customer-specific backup
policies — supply your own via var.management[region].management_backup_rsv_vm_backup_policy
and override var.backup_policy_names with your policy name list per region.

When true, user-supplied policies merge with SCC defaults (user keys win on
collision), so you can extend the default tier list with additional custom
tiers without disabling the SCC defaults entirely.
DESCRIPTION
}

variable "backup_policy_tag_name" {
  type        = string
  default     = "BackupPolicy"
  description = <<-DESCRIPTION
Name of the VM tag that drives backup policy selection. SCC default is
'BackupPolicy'. Customers using different tag conventions can override
(e.g. 'backup_policy', 'RetentionPolicy').

Must match the tagName parameter on the subscription-level backup policy
assignments (main.policy.backup.tf) and the Azure Policy Modify assignment
in alz-mgmt that defaults this tag on untagged VMs.
DESCRIPTION
}

variable "maintenance_window_tag_name" {
  type        = string
  default     = "MaintenanceWindow"
  description = <<-DESCRIPTION
Name of the VM tag that drives Azure Update Manager dynamic scope selection.
SCC default is 'MaintenanceWindow'. Customers using different conventions
can override (e.g. 'patch_wave', 'update_schedule').

Must match the tag key used in the maintenance configuration dynamic scopes
defined in alz-mgmt (.scc-maintenance.auto.tfvars).
DESCRIPTION
}

variable "backup_policy_names" {
  type        = map(list(string))
  default     = null
  description = <<-DESCRIPTION
Per-region list of backup policy names that should have a subscription-level
Azure Policy assignment. The module creates one assignment per (region, policy_name)
combination, each scoped by `<backup_policy_tag_name> = <policy_name>` — VMs
tagged with the matching policy name are registered against that policy in
the vault.

Tag value matches the policy name EXACTLY. This makes the model trivial for
customers with N policies per region (no tier abstraction to maintain), at
the cost of region-specific tag values when policy names include the region
abbreviation (e.g. CAF naming).

When null (default), the module auto-derives the list from the merged backup
policies (SCC defaults + any user-supplied policies via var.management). To
register only a subset of vault policies against subscription-level
assignments, override with the explicit list.

Example for a customer with two custom policies in uksouth:
  backup_policy_names = {
    uksouth = ["pol-myapp-prod-aggressive-uks-001", "pol-myapp-prod-relaxed-uks-001"]
    ukwest  = ["pol-myapp-prod-aggressive-ukw-001", "pol-myapp-prod-relaxed-ukw-001"]
  }
DESCRIPTION
}

variable "backup_policy_fallback_name_per_region" {
  type        = map(string)
  default     = null
  description = <<-DESCRIPTION
Per-region backup policy name to register VMs against when they don't have
a valid <backup_policy_tag_name> tag. The fallback subscription-level policy
assignment uses the "without tag" variant (09ce66bc) and excludes all known
policy names, so VMs with an invalid/missing tag get this policy as a safety
net.

When null (default), uses the SCC `basic` tier policy for each region (the
auto-generated CAF-named pol-rsv-<workload>-<env>-basic-<region>-<instance>).
Override when using customer-specific policies — must match a policy name
that exists in the vault for that region.

Example:
  backup_policy_fallback_name_per_region = {
    uksouth = "pol-myapp-prod-default-uks-001"
    ukwest  = "pol-myapp-prod-default-ukw-001"
  }
DESCRIPTION
}
