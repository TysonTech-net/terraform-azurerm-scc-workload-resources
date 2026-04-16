###############################################################################
# VM Backup Policy Assignment Variables
###############################################################################
# Configuration inputs for the subscription-level VM backup policy assignment
# defined in main.policy.backup.tf. Keeps policy-assignment-specific variables
# grouped separately from the broader compute/management variables for clarity.
###############################################################################

variable "vm_backup_policy_name" {
  type    = string
  default = "SCC-BasicRetention"

  description = <<-DESCRIPTION
Name of the VM backup policy inside the Recovery Services Vault that the
subscription-level backup policy assignment should target.

Defaults to "SCC-BasicRetention" which is one of three policies baked into
the vault by scc-workload-management v1.1.0+:
  - SCC-BasicRetention    : 30 days daily (dev/test, short-term recovery)
  - SCC-StandardRetention : 14 daily + 4 weekly + 3 monthly (default prod)
  - SCC-ExtendedRetention : 14 daily + 4 weekly + 12 monthly + 7 yearly
                            (regulatory/compliance retention)

Override to a different tier for workloads with specific retention needs, or
to a custom policy name if `deploy_scc_default_backup_policies` is false in
the management module and user-supplied policies use different names.

The full resource path is constructed as:
  <vault-resource-id>/backupPolicies/<this-value>

If the named policy does not exist in the vault, the DeployIfNotExists
remediation will fail at apply time with a "policy not found" error.
DESCRIPTION
}
