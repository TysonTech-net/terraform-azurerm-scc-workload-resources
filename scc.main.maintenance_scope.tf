###############################################################################
# SCC Custom: Maintenance Configuration Dynamic Scopes
###############################################################################
# Creates subscription-level dynamic scope assignments for Azure Update Manager
# maintenance configurations. Each assignment targets VMs in THIS subscription
# that have a matching MaintenanceWindow tag.
#
# The maintenance configurations themselves live in platform_shared (management
# subscription) and their resource IDs are read via terraform_remote_state.
# Dynamic scope assignments are subscription-scoped resources: they only match
# VMs in the subscription where the assignment is created. This is why each
# workload platform must create its own dynamic scope assignments rather than
# relying on a central assignment in platform_shared.
#
# OS type filtering is derived from the config key naming convention:
#   - Key contains "linux"   → filter to Linux VMs only
#   - Key contains "windows" → filter to Windows VMs only
#   - Otherwise              → both Linux and Windows (e.g. "patch_wave_1")
#
# This convention matches the SCC maintenance config keys defined in
# alz-mgmt (.scc-maintenance.auto.tfvars).
###############################################################################

locals {
  # Only create dynamic scopes when:
  # 1. Maintenance configurations exist in platform_shared
  # 2. Compute is enabled (VMs exist to target)
  #
  # The "not_supported" key is excluded: it's a sentinel value used for VMs
  # that can't use AUM (e.g. Tenable marketplace images). There's no
  # maintenance configuration with that key.
  maintenance_dynamic_scope_configs = {
    for key, resource_id in local.scc_maintenance_configuration_resource_ids :
    key => {
      resource_id = resource_id
      os_types = (
        strcontains(lower(key), "linux") ? ["Linux"] :
        strcontains(lower(key), "windows") ? ["Windows"] :
        ["Linux", "Windows"]
      )
    }
    if var.compute_enabled
  }
}

resource "azurerm_maintenance_assignment_dynamic_scope" "scc" {
  for_each = local.maintenance_dynamic_scope_configs

  name                         = "dscope-${each.key}-${substr(var.subscription, 0, 8)}"
  maintenance_configuration_id = each.value.resource_id

  filter {
    locations       = []
    os_types        = each.value.os_types
    resource_groups = []
    resource_types  = ["Microsoft.Compute/virtualMachines"]
    tag_filter      = "Any"

    tags {
      tag    = var.maintenance_window_tag_name
      values = [each.key]
    }
  }
}
