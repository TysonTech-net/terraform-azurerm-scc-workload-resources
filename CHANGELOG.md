# Changelog

All notable changes to this module are documented in this file. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
