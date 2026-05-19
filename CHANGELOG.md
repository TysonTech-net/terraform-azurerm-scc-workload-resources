# Changelog

All notable changes to this module are documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.10.0] - 2026-05-19

### Added

- **Canonical SCC hub contract.** The module now reads `scc_hub_router_private_ip_addresses`, `scc_firewall_subnet_address_prefixes`, and `scc_bastion_subnet_address_prefixes` from hub state as the canonical source of truth for hub-derived values. Consuming `<customer>-alz-mgmt` hub repos should expose these outputs in `scc.outputs.contract.tf` (or equivalent), regardless of the underlying hub topology (AzFw, NVA, VWAN, hybrid). See README "Hub topology" section.
- **Caller-side overrides** for hub-state lookups: `hub_router_private_ip_override`, `hub_router_subnet_address_prefixes_override`, `bastion_subnet_address_prefixes_override` (all `map(string)`, region-keyed, default `{}`). When set, beats both the canonical SCC output and the legacy AVM-stock output. Includes IPv4/CIDR validation blocks.
- **Per-subnet `allow_vnet_inbound` flag** (`optional(bool, false)` in the vending subnet schema). When true, the orchestrator-generated default NSG for that subnet emits an additional `AllowVnetInBound` rule at priority 3998 (VirtualNetwork → VirtualNetwork, any protocol/port). Ergonomic opt-in for plink subnets hosting consumer Private Endpoints.
- **`additional_nsg_rules`** input (`map(map(security_rule_object))`, default `{}`). Additive escape hatch for caller-supplied NSG rules merged into the orchestrator's default NSG. Keyed by the NSG key (`nsg-{region}-{vnet_key}-{subnet_key}`), then by rule name.

### Changed

- **Hub-derived locals refactored** to a three-tier resolution: caller override → canonical SCC output → legacy AVM-stock output → empty. Existing consumers whose hub repos expose only AVM-stock outputs continue to work via the legacy fallback path. New consumers should populate the SCC outputs.
- **Default NSG hub-allow rules** (`AllowFirewallInBound`, `AllowBastionInBound`) are now emitted conditionally — only when the corresponding source CIDR is known from hub state or via override. Previously, missing hub data fell through to a hardcoded `"10.0.0.0/26"` / `"10.0.0.64/26"` literal, producing no-op allow rules in any deployment whose hub subnets aren't at those exact CIDRs. The literal fallback is removed.

### Migration guidance

- **Existing AzFw-only consumers** (e.g. moj-eslz): no required hub-repo change. The legacy fallback continues to read `hub_and_spoke_vnet_firewall_private_ip_address`. To unlock the per-subnet `allow_vnet_inbound` flag and the `additional_nsg_rules` map, just bump the module ref to `v1.10.0` in the workload repo's `terraform.tf`. Expected plan diff: zero changes when no new variables are set.
- **NVA / non-AzFw consumers** (e.g. BBSWE): add a `scc.outputs.contract.tf` to the hub repo exposing `scc_hub_router_private_ip_addresses`, `scc_firewall_subnet_address_prefixes`, and `scc_bastion_subnet_address_prefixes` mapped to hub keys (`primary` / `secondary` matching `hub_region_mapping`). After the hub PR merges and applies, workload repos that bump to `v1.10.0` will start generating the default route table and emit hub-allow NSG rules with the correct CIDRs.
- **Hardcoded `10.0.0.0/26` fallback removal**: if your hub firewall subnet really was at `10.0.0.0/26` and you relied on the literal, set `hub_router_subnet_address_prefixes_override = { <region> = "10.0.0.0/26" }` or expose `scc_firewall_subnet_address_prefixes` from the hub. Otherwise the AllowFirewallInBound rule is omitted and your NSG falls back to AzureLoadBalancer + DenyAll only.

### Compatibility

- Backwards-compatible. All new variables default to `{}` / `false`. The legacy AVM-stock output path is preserved as a fall-through.

## Earlier versions

Earlier versions of this module are not catalogued here; see `git log` for the full history.
