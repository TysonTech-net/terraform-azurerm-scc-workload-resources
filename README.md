# terraform-azurerm-scc-workload-resources

Multi-region workload vending stack for Azure Landing Zones. Orchestrates subscription vending, workload management, and compute deployment.

## Usage

```hcl
module "workload_resources" {
  source = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-workload-resources.git?ref=v1.0.0"

  subscription          = var.subscription
  naming                = var.naming
  connectivity_type     = var.connectivity_type
  platform_shared_state = var.platform_shared_state
  hub_region_mapping    = var.hub_region_mapping
  tags                  = var.tags
  vending               = var.vending
  management            = var.management
  compute               = var.compute
}
```

## What It Orchestrates

- [AVM Subscription Vending](https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest) (resource groups, VNets, NSGs, route tables, UMIs, role assignments)
- [scc-workload-management](https://github.com/TysonTech-net/terraform-azurerm-scc-workload-management) (Recovery Services Vault, Key Vault, Update Manager, SCC standard backup policies)
- [scc-workload-vm](https://github.com/TysonTech-net/terraform-azurerm-scc-workload-vm) (Virtual Machines with AVM, backup, maintenance, ASR/BCDR)
- Tag-based subscription-level VM backup policy assignments (one per SCC backup tier + fallback for untagged VMs). Change the `BackupPolicy` tag value to move a VM between retention tiers.
- VM tag injection for operational tagging: `MaintenanceWindow` (Update Manager dynamic scoping), `sccosmanagement`/`sccnetworkmanagement` (Logic Monitor collector assignment), `BackupPolicy` (backup retention tier selection).

## VM Backup Policy Selection

Set `backup_policy` on a VM to the exact name of the backup policy you want it registered against. The tag value matches the policy name in the vault — no abstraction layer. This trivially supports customers with N policies per region.

SCC standard policies are deployed into each vault with CAF-auto-generated names: `pol-rsv-<workload>-<env>-<tier>-<region>-<instance>`. The three default tiers:

| Tier | CAF policy name | Daily | Weekly | Monthly | Yearly | Use case |
|---|---|---|---|---|---|---|
| basic | `pol-rsv-<workload>-<env>-basic-<region>-001` | 30 days | — | — | — | Dev/test (default fallback) |
| standard | `pol-rsv-<workload>-<env>-standard-<region>-001` | 14 days | 4 weeks | 3 months | — | Production |
| extended | `pol-rsv-<workload>-<env>-extended-<region>-001` | 14 days | 4 weeks | 12 months | 7 years | Compliance |

Example VM tag value (identity workload, prod, instance 001, uksouth, basic): `pol-rsv-identity-prod-basic-uks-001`.

A fallback assignment catches VMs without a valid `BackupPolicy` tag and registers them against the per-region fallback policy (default: SCC basic tier for the region; configurable via `var.backup_policy_fallback_name_per_region`).

Toggle SCC defaults via `var.deploy_scc_default_backup_policies`.

### Customising

- **Different tag name**: set `var.backup_policy_tag_name` (default `"BackupPolicy"`) — also update the Modify/Audit assignments in alz-mgmt to match.
- **Different policies**: disable SCC defaults (`deploy_scc_default_backup_policies = false`), supply your own via `management.<region>.management_backup_rsv_vm_backup_policy`, and override `var.backup_policy_names` with the per-region list of policy names that need subscription-level assignments.
- **Different fallback policy**: set `var.backup_policy_fallback_name_per_region` to a per-region map of policy names.
- **Different maintenance window tag**: set `var.maintenance_window_tag_name` (default `"MaintenanceWindow"`).

## VM Credential Paths

VM admin credentials resolve in this priority order:

1. **Explicit per-VM** (`admin_password` in the VM tfvars) — used as-is
2. **Env-injected fallback** (`var.vm_admin_password` via `TF_VAR_vm_admin_password`) — used when per-VM is unset
3. **Auto-generated** (Windows VMs only, when `compute_auto_credential_keyvault_enabled = true` and regional Key Vault is deployed) — 22-char random password stored in KV

Linux VMs skip the auto-generation path and use SSH keys (handled separately by the AVM VM module via `tls_private_key`). Existing VMs with baked admin passwords can opt in to KV storage via `store_password_in_keyvault = true` to avoid the OS disk recreation that dropping the password would trigger.

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.12 |
| azurerm | ~> 4.0 |
| azapi | ~> 2.0 |
