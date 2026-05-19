# terraform-azurerm-scc-workload-resources

Multi-region workload vending stack for Azure Landing Zones. Orchestrates subscription vending, workload management, and compute deployment.

## Usage

```hcl
module "workload_resources" {
  source = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-workload-resources.git?ref=v1.10.0"

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
- [scc-workload-management](https://github.com/TysonTech-net/terraform-azurerm-scc-workload-management) (Recovery Services Vault, Key Vault, Update Manager)
- [scc-workload-vm](https://github.com/TysonTech-net/terraform-azurerm-scc-workload-vm) (Virtual Machines with AVM, backup, maintenance, ASR/BCDR)

## Hub topology

The module is customer-agnostic. All customer-specificity lives in the consuming `<customer>-alz-mgmt` hub repo — the module's contract is "read a stable set of well-named SCC outputs from hub state". Whatever the hub actually deployed (Azure Firewall, Palo Alto NVA, third-party SD-WAN, hybrid) is the hub repo's responsibility; the module just trusts the outputs.

### Canonical SCC outputs the module reads

Each consuming `<customer>-alz-mgmt` repo should expose these outputs from a `scc.outputs.contract.tf` file (or equivalent), regardless of the underlying hub implementation. Shape: `map(hub_key → value)` where the hub key is whatever the consumer's `hub_region_mapping` translates to a region name.

| Output | Value | Used for |
|---|---|---|
| `scc_hub_router_private_ip_addresses` | IPv4 string per hub key — next-hop IP for spoke-egress UDRs | Default route table generation |
| `scc_firewall_subnet_address_prefixes` | CIDR string per hub key — source CIDR for `AllowFirewallInBound` | Default NSG hub-allow rule |
| `scc_bastion_subnet_address_prefixes` | CIDR string per hub key — source CIDR for `AllowBastionInBound` | Default NSG bastion-allow rule |

Examples of how a hub repo populates these:

- Azure Firewall hub: `value = module.hub_and_spoke_vnet[0].firewall_private_ip_addresses` (one-line wrap around the stock AVM output).
- NVA hub: explicit references to NVA load-balancer / VM front-end IPs.
- Virtual WAN hub: wrap whichever VWAN output carries the firewall private IP.
- Hybrid: `coalesce()` across the conditional hub modules.

### Resolution order

For each hub-derived value the module resolves in this order; first non-empty wins.

1. **Caller override** (`var.hub_router_private_ip_override`, `var.hub_router_subnet_address_prefixes_override`, `var.bastion_subnet_address_prefixes_override`) — per-workload bypass; defaults to `{}`.
2. **Canonical SCC output** from hub state — the documented contract.
3. **Legacy AVM-stock output** (`hub_and_spoke_vnet_firewall_private_ip_address` etc.) — backwards-compatible fallback for hubs that haven't adopted the SCC contract yet.
4. **Empty** — silent no-op (e.g. a VWAN hub that doesn't expose a firewall IP). Route tables and hub-allow NSG rules are skipped in this case.

New consumers should populate (2). Existing AzFw-only consumers continue working via (3) until they add the SCC contract outputs.

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
