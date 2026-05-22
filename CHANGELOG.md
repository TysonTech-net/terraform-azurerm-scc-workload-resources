# Changelog

All notable changes to this module are documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.12.1] - 2026-05-22

### Fixed

- **Bump workload-vm pin v1.4.0 → v1.4.1** to pick up the auto-AvSet RG resolution fix. v1.4.0's `coalesce(try(...), try(...))` for the auto-AvSet RG name failed whenever both branches resolved to null — hit by every consumer calling the module against a zoned region (UKS has zones, so `_auto_avset_enabled = false` for that region, but the local still evaluated and crashed). v1.4.1 gates the entire expression on `_auto_avset_enabled` and uses `try()` (which permits null fallback) inside.

### Compatibility

- Bug-fix release. No new variables, no API changes. v1.12.0 consumers MUST bump to v1.12.1; v1.12.0 plan errors with `Call to function "coalesce" failed` on any workload calling the module from a zoned region.

## [1.12.0] - 2026-05-22

### Added

- **Per-VM `enabled` toggle.** New optional `enabled = optional(bool, true)` field on the VM object in `var.compute[<region>].vms[<key>]`. When `false`, NO resources are created for that VM — no NICs, no disks, no role assignments, no backup protection, no maintenance assignment, no Key Vault secret. The VM block stays in tfvars so operational metadata is preserved.
- Filter is applied in `local.compute_vms_with_resolved_subnets` (`main.compute.tf:42-46`) via an `if try(vm.enabled, true)` clause, so every downstream local (credentials, sub-level policy assignments, the workload-vm module call) naturally skips disabled VMs.
- AND-ed with the existing region-level `compute_enabled`: both must be true for a VM to deploy. Useful for parking individual VMs (capacity hold on one role, marketplace EULA pending, scheduled decom staging) without commenting out the HCL block.

### Changed

- **Workload-vm child module bumped to v1.4.0.** Pulls in auto-create Availability Set for zoneless regions (e.g. UK West). When a workload's region has no AZs, the module now creates one AvSet per region and joins every VM to it without requiring tfvars work. Per-VM override via `availability_set_resource_id` still wins. Zoned regions (e.g. UK South) continue to use per-VM `zone` placement as before.

### Compatibility

- Non-breaking. Backwards-compatible with v1.11.x consumers — workload tfvars don't need updating unless they want to use the new toggle. The field defaults to `true`. The workload-vm v1.4.0 bump is also non-breaking (default `auto_create_availability_set = true` only fires in zoneless regions).

## [1.11.2] - 2026-05-20

### Fixed

- **NSG security rule descriptions cannot exceed 140 characters.** Azure REST API rejects with `SecurityRuleDescriptionTooLong` at apply time. v1.11.0 expanded the `AllowFirewallInBound` and `AllowBastionInBound` rule descriptions to include the variable names that gate them; the result was 158–175 characters, over the limit. Plan succeeded, apply failed.
- **Fix**: trimmed descriptions to ≤120 characters. Same intent, shorter wording.

### Compatibility

- Bug-fix release. No new variables, no API changes. Bump module ref `v1.11.1` → `v1.11.2`.

## [1.11.1] - 2026-05-20

### Fixed

- **NSG default rules with service-tag / wildcard sources rejected by Azure.** v1.11.0 switched all default NSG rules to `source_address_prefixes` (plural list) for type-stable composition with the new list-shape input variables. Azure's NSG REST API rejects service tags (`"AzureLoadBalancer"`, `"VirtualNetwork"`, `"Internet"`, `"*"`) when placed in `sourceAddressPrefixes`: error `SecurityRuleParameterContainsUnsupportedValue` at apply time. The constraint is documented (cryptically) and only enforced at the API layer, so plan succeeds but apply fails.
- **Fix**: rules with service-tag/wildcard sources (`AllowAzureLoadBalancerInBound`, `DenyAllInBound`, `AllowVnetOutBound`, `AllowInternetOutBound`, `DenyAllOutBound`, `AllowVnetInBound`) now use `source_address_prefix` (singular). Rules with workload-supplied CIDR lists (`AllowFirewallInBound`, `AllowBastionInBound`) keep `source_address_prefixes` (plural). All rules declare BOTH fields with one set to `null` for type-stable composition across the merged rule map.

### Compatibility

- Bug-fix release. No new variables, no API changes. Backwards-compatible with v1.11.0 — workload tfvars don't need updating.
- v1.11.0 consumers should bump to v1.11.1 immediately; v1.11.0 apply will fail on any NSG with default rules.

## [1.11.0] - 2026-05-20

### BREAKING CHANGES

- **Dropped SCC bolt-on outputs.** v1.11.0 reads ONLY accelerator-stock `outputs.tf` from hub state. The three `scc_*` outputs (`scc_hub_router_private_ip_addresses`, `scc_firewall_subnet_address_prefixes`, `scc_bastion_subnet_address_prefixes`) introduced in v1.10.0 are no longer read. Hub repos can delete them once all consumers are on v1.11.0.
- **Variable renames** (workload tfvars require updating at v1.11.0 bump):
  - `hub_router_subnet_address_prefixes_override` (`map(string)`) → `hub_router_subnet_address_prefixes` (`map(list(string))`)
  - `bastion_subnet_address_prefixes_override` (`map(string)`) → `bastion_subnet_address_prefixes` (`map(list(string))`)
  - `_override` suffix dropped because these are first-class required inputs in v1.11.0 (no hub-state fallback for subnet CIDRs — the AVM hub pattern module has no native subnet-CIDR outputs).
  - Shape changed from string to `list(string)` per region to accommodate multi-NIC NVA clusters spanning multiple subnets. Single-element lists are normal for AzFw and single-NIC NVAs.
- **Required inputs when default NSG rules enabled.** With `enable_default_nsg = true`:
  - `enable_default_nsg_firewall_rule = true` (default) → `hub_router_subnet_address_prefixes` REQUIRED per region in `vending`.
  - `enable_default_nsg_bastion_rule = true` (default) → `bastion_subnet_address_prefixes` REQUIRED per region.
  - Missing inputs fail plan via a `precondition` block with an actionable error message naming the missing variable and region.
- **Legacy AVM fallback removed.** Resolution chain for hub router IP simplified from `override → SCC → hub_and_spoke_vnet_firewall_private_ip_address → empty` to `override → dns_server_ip_address → fail`. The AVM `dns_server_ip_address` output is already topology-agnostic (returns the AzFw private IP when firewall is deployed, returns `var.hub_virtual_networks.X.hub_virtual_network.hub_router_ip_address` for NVA mode), so the legacy fallback was redundant.
- **NSG rule shape: `source_address_prefix` → `source_address_prefixes`** (plural). All default rules now use the list-shape source field for type-stable composition with the new list-shape input variables. `source_address_prefix` is set to `null` on all default rules.

### Added

- **Per-rule NSG toggles** (`bool`, default `true`):
  - `enable_default_nsg_firewall_rule` — when false, `AllowFirewallInBound` source falls through to `["0.0.0.0/32"]` (non-matchable). Useful for PaaS-only workloads with no spoke→hub return traffic.
  - `enable_default_nsg_bastion_rule` — same shape for `AllowBastionInBound`. Useful for workloads with no Bastion-reachable admin path.
- **`terraform_data.validate_hub_router_inputs`** resource (one per region in `vending`) — hosts the precondition blocks that fire at plan time with clear actionable errors when required inputs are missing.

### Changed

- **Hub contract simplified to ONE output**: `dns_server_ip_address` (already stock in every accelerator-generated hub). Same contract works for moj-eslz (AzFw), BBSWE (NVA), and any future customer regardless of hub topology.
- **`dns_ips_raw` local renamed to `hub_router_ips_raw`** internally (purely semantic — the value IS the hub router IP, which happens to also be the VNet DNS server in typical hub-and-spoke patterns).

### Migration guidance

Workload repo (per repo, after module tag exists):

1. Bump `?ref=v1.10.2` → `?ref=v1.11.0` in `main.tf`.
2. Update workload `variables.tf` to declare the renamed + new variables (`hub_router_subnet_address_prefixes`, `bastion_subnet_address_prefixes`, `enable_default_nsg_firewall_rule`, `enable_default_nsg_bastion_rule`).
3. Update workload `main.tf` to pass the new variables to the module.
4. Update workload `.platform-<workload>.auto.tfvars` to:
   - Rename `*_override` keys to drop the suffix.
   - Convert single-string values to single-element lists: `"172.16.0.96/27"` → `["172.16.0.96/27"]`.
   - Add new entries per region present in `vending`.
5. Local `terraform plan` — expect: 2 new `terraform_data.validate_hub_router_inputs` resources per region (no-ops), 4 NSG in-place updates per region (source field switched to plural — cosmetic, end-state functionally unchanged).
6. Apply via your usual CD path.

Hub repo (one-time per customer, AFTER all consumers on v1.11.0):

- Delete `scc_hub_router_private_ip_addresses`, `scc_firewall_subnet_address_prefixes`, `scc_bastion_subnet_address_prefixes` outputs from `scc.outputs.*.tf`. Plan should show zero resource changes (outputs are metadata).

### Compatibility

- **Breaking.** Workload tfvars require the variable rename and shape change. The module will fail plan with clear precondition errors until tfvars are updated.
- moj-eslz consumers: out of scope. Per BBSWE owner 2026-05-20, moj will fork from its current module version if needed.

### Why

User-driven decision (2026-05-20):
- The accelerator-stock `outputs.tf` already exposes everything needed for the next-hop IP via `dns_server_ip_address` (topology-agnostic via AVM internal logic). No reason to maintain a parallel `scc_*` contract.
- Subnet CIDRs aren't natively exposed by the AVM hub pattern module, and TF can't filter subnets by IP-in-CIDR. Data-source auto-discovery would require subnet-name input + cross-sub RBAC + slower plans, saving zero work for any non-AzFw customer. Workload tfvars input is cheaper and clearer.
- Tight subnet-scoped NSG rules (not hub-VNet-wide) for least-privilege; per-rule toggles allow workloads with no Bastion/firewall flow to opt out.

## [1.10.2] - 2026-05-19

### Fixed

- **Per-NSG type variance from `allow_vnet_inbound` conditional injection.** v1.10.0 + v1.10.1 attempted to inject `AllowVnetInBound` into `default_network_security_groups[<plink-NSG>].security_rules` only when the per-subnet flag was true. Every variant tried (`condition ? {rule} : {}`, `for-with-if`, `tomap()` cast, schema-coerce via `merge(schema, rule)`) still produced per-NSG `security_rules` type variance — Terraform inferred `default_network_security_groups` as `object` with per-NSG named attributes instead of `map`, breaking the downstream `merged_network_security_groups` conditional with "Inconsistent conditional result types". Root cause: any conditional-presence pattern at the per-subnet level changes the inferred shape of the outer collection.
- **Fix: always-emit `AllowVnetInBound`, conditional source CIDR.** The rule is now part of `default_nsg_security_rules_by_region` and appears on every default NSG. `source_address_prefix` is `"VirtualNetwork"` when `subnet.allow_vnet_inbound = true`, otherwise `"0.0.0.0/32"` (non-matchable IP, effective no-op). Same shape across all NSGs eliminates the type variance.
- **`var.additional_nsg_rules` no longer participates in the default NSG merge.** Same type-variance class of problem (the typed variable's `map(map(object))` doesn't unify with the inline default rules' inferred type). The variable is kept in the module for backwards compatibility but is now a no-op. Callers needing additional rules should provide a full custom NSG via `vending.<region>.network_security_groups` and reference it from the subnet's `network_security_group.key_reference` — the existing escape hatch.
- **Default `AllowFirewallInBound` / `AllowBastionInBound` always emitted** (no longer gated by hub-state presence). When the hub CIDR is unknown, source falls through to `"0.0.0.0/32"`. Conditional emission produced the same type-variance class of problem.

### Compatibility

- Bug-fix release. No new variables, no API changes.
- Backwards-compatible with v1.10.x consumers; resolves the inferred-object-vs-map error that prevented any consumer using the per-subnet `allow_vnet_inbound` flag from planning.
- `var.additional_nsg_rules` accepts the same shape as v1.10.0+ but is silently ignored. Will be reconsidered in a future release once a type-stable mechanism is designed.

## [1.10.1] - 2026-05-19

### Fixed

- **Subnet route-table auto-assignment now respects `enable_default_route_table = false`.** Previously, `main.vending.tf` auto-assigned `route_table.key_reference = "rt-${region}"` to every subnet whenever the hub firewall private IP was known (driving `default_route_tables` population), regardless of whether the toggle would actually allow that RT to land in `merged_route_tables`. With the toggle set to `false`, subnets ended up referencing an RT key that sub-vending then couldn't resolve, causing a `coalesce` error at plan: `local.virtual_network_subnet_route_table_available_resource_ids is object with no attributes`. Pre-existing bug, latent until a consumer set the toggle to `false` (BBSWE-Nerdio v1.10.0 first hit). Fix: the auto-assignment now also checks `var.enable_default_route_table`.
- **Type-stable NSG rule merge.** v1.10.0's `default_network_security_groups` used `condition ? {key = rule} : {}` patterns for conditional `AllowVnetInBound` injection and for `var.additional_nsg_rules` lookups. The true/false branches had different object shapes, which made Terraform infer per-NSG security_rules types inconsistently. The outer `default_network_security_groups` was then inferred as `object` (per-NSG named attributes) instead of `map`, breaking the downstream `merged_network_security_groups` conditional. Fix: both conditional sources now use `{ for k, v in {...} : k => v if <condition> }` which preserves a stable `map(rule_object)` type whether the filter matches or not.

### Compatibility

- Bug-fix release only. No new variables, no API changes. Backwards-compatible with v1.10.0 consumers; resolves the type-inference and dangling-RT-reference errors that prevented `enable_default_route_table = false` + `allow_vnet_inbound = true` working together.

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
