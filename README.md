# terraform-azurerm-scc-workload-resources

Multi-region workload vending stack for Azure Landing Zones. Orchestrates subscription vending, workload management, and compute deployment.

## Usage

```hcl
module "workload_resources" {
  source = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-workload-resources.git?ref=v1.11.0"

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

SCC standard policies are deployed into each vault with constant names — same across all vaults, regions, and workloads:

| Policy name | Daily | Weekly | Monthly | Yearly | Use case |
|---|---|---|---|---|---|
| `SCC-BasicBackup` | 30 days | — | — | — | Dev/test (default fallback) |
| `SCC-StandardBackup` | 14 days | 4 weeks | 3 months | — | Default production |
| `SCC-ExtendedBackup` | 14 days | 4 weeks | 12 months | 7 years | Compliance/regulatory |

Example VM tag value: `SCC-StandardBackup`. Same value works across all regions and workloads — no need to vary per VM.

A fallback assignment catches VMs without a valid `BackupPolicy` tag and registers them against the per-region fallback policy (default: `SCC-BasicBackup`; configurable via `var.backup_policy_fallback_name_per_region`).

Customer-supplied additional policies (via `var.management[region].management_backup_rsv_vm_backup_policy`) can use any naming convention — only the SCC defaults follow the constant naming. Tag those VMs with the exact name of your custom policy.

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

## Hub topology

The module is customer-agnostic. The hub-state contract is intentionally minimal — ONE remote-state output (`dns_server_ip_address`, accelerator-stock in every ALZ hub repo) plus workload-tfvars-supplied subnet CIDRs for the default NSG inbound rules.

### Hub-side contract: ONE output, zero hub-repo work

Every accelerator-generated ALZ hub repo (`outputs.tf`) exposes `dns_server_ip_address` out of the box. The AVM hub-and-spoke pattern module's underlying logic returns the right value for both topologies:

- AzFw hub: returns the deployed Azure Firewall's private IP per region.
- NVA hub: returns `var.hub_virtual_networks.<key>.hub_virtual_network.hub_router_ip_address` (the NVA front-end LB IP or single-VM IP).

No `scc.outputs.*.tf` bolt-on. No customer-specific contract file. The module reads `dns_server_ip_address` from remote state and uses it as the next-hop IP for the default route table.

### Workload-side inputs

Subnet CIDRs for the default NSG inbound rules are NOT exposed by the AVM hub pattern module (no native subnet-CIDR outputs). Workload tfvars supply them per region:

```hcl
hub_router_subnet_address_prefixes = {
  uksouth = ["172.16.0.96/27"]   # AzFw subnet CIDR OR NVA trust subnet CIDR
  ukwest  = ["172.24.0.96/27"]
}

bastion_subnet_address_prefixes = {
  uksouth = ["172.16.0.0/26"]    # Azure Bastion subnet CIDR
  ukwest  = ["172.24.0.0/26"]
}
```

List shape supports multi-NIC NVA clusters spanning multiple subnets. Single-element lists are normal for AzFw and single-NIC NVAs.

### Per-rule opt-out

For workloads that don't need a particular default NSG rule (e.g. PaaS-only with no spoke→hub return traffic, or no Bastion-reachable admin path), set the per-rule toggle to false. The corresponding subnet CIDR variable becomes optional:

```hcl
enable_default_nsg_firewall_rule = false   # AllowFirewallInBound omitted
enable_default_nsg_bastion_rule  = false   # AllowBastionInBound omitted
```

### Resolution chain (per hub-derived value)

For the next-hop IP (used by the default route table):

1. **Caller override**: `var.hub_router_private_ip_override[<region>]` — optional, beats remote state.
2. **Accelerator-stock**: `dns_server_ip_address` from hub remote state — default path.
3. **Fail**: precondition error if `enable_default_route_table = true` and neither resolves.

For NSG inbound rule source CIDRs (firewall + bastion):

1. **Workload tfvars**: `var.hub_router_subnet_address_prefixes[<region>]` / `var.bastion_subnet_address_prefixes[<region>]` — required when the corresponding per-rule toggle is true.
2. **Fail**: precondition error if the rule is enabled and the variable is missing for the region.

Errors at plan time name the missing variable AND the region, so the fix is obvious.

### Migration from v1.10.x

Variable renames + shape changes (BREAKING):
- `hub_router_subnet_address_prefixes_override` (`map(string)`) → `hub_router_subnet_address_prefixes` (`map(list(string))`)
- `bastion_subnet_address_prefixes_override` (`map(string)`) → `bastion_subnet_address_prefixes` (`map(list(string))`)

In your workload tfvars, drop `_override` and convert single-string values to single-element lists:

```hcl
# Before (v1.10.x)
hub_router_subnet_address_prefixes_override = {
  uksouth = "172.16.0.96/27"
}

# After (v1.11.0)
hub_router_subnet_address_prefixes = {
  uksouth = ["172.16.0.96/27"]
}
```

Hub-side `scc_*` outputs can be deleted after all consumers migrate. See CHANGELOG `1.11.0` entry for the full migration recipe.

## Customisation surface

### Per-subnet ergonomic flags (in `vending.<region>.virtual_networks.<vnet>.subnets.<subnet>`)

- `allow_vnet_inbound = true` — restores the Azure system-default `AllowVnetInBound` rule (priority 3998) on this subnet's auto-generated NSG. Required for plink subnets hosting consumer Private Endpoints, where intra-VNet traffic must reach the PE NIC. The orchestrator's default NSG deliberately omits this rule to force east-west traffic through the hub for inspection; set this flag to `true` for any subnet that holds PEs reached from the same VNet.

### Module-level overrides

- `hub_router_private_ip_override`, `hub_router_subnet_address_prefixes_override`, `bastion_subnet_address_prefixes_override` — bypass the hub-state lookup entirely for one or more regions. Keyed by region name.
- `additional_nsg_rules` — additive map of `{ "<nsg-key>" = { "<rule-key>" = { ... } } }` merged into the orchestrator's default NSG for matching subnets. The NSG key format is `nsg-{region}-{vnet_key}-{subnet_key}`, matching `local.default_network_security_groups` in `main.vending.tf`. Use this as an escape hatch when the per-subnet flag isn't expressive enough.

For a complete replacement of the auto-generated NSG (rather than additive rules), supply a full custom NSG via `vending.<region>.network_security_groups` and reference it from the subnet's `network_security_group.key_reference`.

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.12 |
| azurerm | ~> 4.0 |
| azapi | ~> 2.0 |
