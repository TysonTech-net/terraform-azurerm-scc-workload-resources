###############################################################################
# SCC Backup Tier + Operational Tag Variables
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
Deploy SCC standard VM backup policy tiers (basic, standard, extended) into
each deployed Recovery Services Vault. Names are auto-generated from the
CAF pattern: pol-rsv-<workload>-<env>-<tier>-<region>-<instance>.

Defaults to true. Set false if your deployment uses customer-specific backup
policies — in that case, supply your own tiers via
var.management[region].management_backup_rsv_vm_backup_policy and override
var.backup_policy_tiers with matching policy_name values.

When true, user-supplied policies merge with SCC defaults (user keys win on
collision), so you can extend the default tier list with additional custom
tiers without disabling the SCC defaults entirely.
DESCRIPTION
}

variable "backup_policy_tag_name" {
  type        = string
  default     = "BackupPolicy"
  description = <<-DESCRIPTION
Name of the VM tag that drives backup policy tier selection. SCC default is
'BackupPolicy'. Customers using different tag conventions can override
(e.g. 'backup_tier', 'RetentionPolicy').

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

variable "backup_policy_fallback_tier" {
  type        = string
  default     = "basic"
  description = <<-DESCRIPTION
Which backup tier to register VMs against when they don't have a valid
BackupPolicy tag. The fallback subscription-level policy assignment uses
the "without tag" variant (09ce66bc) and excludes all known tier tag
values, so VMs with an invalid/missing tag get this tier as a safety net.

Must match a key in var.backup_policy_tiers (or one of the SCC default
keys: "basic", "standard", "extended"). Defaults to "basic".
DESCRIPTION
}

variable "backup_policy_tiers" {
  type = map(object({
    policy_name_per_region = optional(map(string))
    policy_name            = optional(string)
    description            = optional(string, "")
  }))
  default     = null
  description = <<-DESCRIPTION
Map of backup policy tiers for subscription-level policy assignments. Each
entry:
  - key: the value that VMs tag themselves with (via backup_policy on the VM
    or the BackupPolicy tag directly) to select this tier
  - policy_name_per_region (preferred): map of region -> backup policy name
    in that region's vault. Use when policy names differ per region (e.g.
    CAF naming with region abbreviation).
  - policy_name (alternative): single backup policy name used across all
    regions. Use when the same policy name exists in every vault.
  - description: optional human-readable description surfaced in Azure
    Portal and compliance views.

When null (default), the module auto-derives tiers from the SCC standard
CAF-named defaults (see scc.locals.backup_tiers.tf). The map key is the
tier short name ("basic", "standard", "extended"), the policy_name_per_region
is populated from the auto-generated CAF policy names.

Override when using customer-specific backup policies — the map keys become
the allowed BackupPolicy tag values, and each entry's policy_name(_per_region)
must match a policy that exists in the Recovery Services Vault. Misalignment
(a tag value that doesn't match any entry, or an entry pointing at a
non-existent policy) will cause remediation failures at apply time.
DESCRIPTION
}
