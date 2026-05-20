###############################################################################
# Plan-time validations for hub-state inputs
###############################################################################
# v1.11.0: workload tfvars supply firewall + bastion subnet CIDRs (no native AVM
# output for those). These preconditions fail plan with a clear actionable error
# if a required input is missing for a region that has hub-routing or default-NSG
# rules enabled.
#
# `terraform_data` is used as the precondition host because module calls don't
# accept lifecycle blocks. Resource is no-op at apply time.

resource "terraform_data" "validate_hub_router_inputs" {
  for_each = var.vending

  triggers_replace = {
    enable_default_route_table       = var.enable_default_route_table
    enable_default_nsg               = var.enable_default_nsg
    enable_default_nsg_firewall_rule = var.enable_default_nsg_firewall_rule
    enable_default_nsg_bastion_rule  = var.enable_default_nsg_bastion_rule
    region                           = each.key
  }

  lifecycle {
    precondition {
      condition = (
        !var.enable_default_route_table
        || try(local.firewall_private_ip_addresses[each.key], null) != null
      )
      error_message = <<-EOT
        Region "${each.key}": enable_default_route_table = true but no hub router IP could be resolved.
        Resolution order tried: var.hub_router_private_ip_override["${each.key}"] (caller override),
        then remote_state.dns_server_ip_address[hub_key] (hub's accelerator-stock output).

        Fix one of:
          - Set var.hub_router_private_ip_override["${each.key}"] = "<hub-router-IPv4>"
          - Ensure the consuming hub repo exposes dns_server_ip_address with an entry for the
            hub_key that var.hub_region_mapping["${each.key}"] resolves to
          - Set var.enable_default_route_table = false if this workload doesn't need the default RT
      EOT
    }

    precondition {
      condition = (
        !(var.enable_default_nsg && var.enable_default_nsg_firewall_rule)
        || try(length(local.firewall_subnet_address_prefixes[each.key]), 0) > 0
      )
      error_message = <<-EOT
        Region "${each.key}": enable_default_nsg_firewall_rule = true but no firewall/NVA subnet
        CIDR was supplied.

        Fix one of:
          - Set var.hub_router_subnet_address_prefixes["${each.key}"] = ["<cidr>", ...] to the
            hub firewall/NVA subnet CIDR(s) (e.g. ["172.16.0.96/27"] for BBSWE NVA trust subnet)
          - Set var.enable_default_nsg_bastion_rule = false if this workload doesn't need the
            AllowFirewallInBound rule (e.g. PaaS-only workloads with no spoke→hub return traffic)
      EOT
    }

    precondition {
      condition = (
        !(var.enable_default_nsg && var.enable_default_nsg_bastion_rule)
        || try(length(local.bastion_subnet_address_prefixes[each.key]), 0) > 0
      )
      error_message = <<-EOT
        Region "${each.key}": enable_default_nsg_bastion_rule = true but no Bastion subnet
        CIDR was supplied.

        Fix one of:
          - Set var.bastion_subnet_address_prefixes["${each.key}"] = ["<cidr>", ...] to the
            Azure Bastion subnet CIDR (e.g. ["172.16.0.0/26"])
          - Set var.enable_default_nsg_bastion_rule = false if this workload has no
            Bastion-reachable admin path (PaaS-only, or JIT-access workloads)
      EOT
    }
  }
}
