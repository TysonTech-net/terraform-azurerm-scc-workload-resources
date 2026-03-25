###############################################################################
# Locals - Auto-Generated Naming Convention
###############################################################################

locals {
  # Region short names from the avm-utl-regions module
  # Uses geo_code if available, otherwise falls back to short_name (derived from display name initials)
  regions_by_name = module.avm_utl_regions.regions_by_name

  # Helper function to get region short name (geo_code or short_name)
  get_region_abbr = {
    for name, region in local.regions_by_name : name => coalesce(
      region.geo_code,
      region.short_name
    )
  }

  # Naming patterns based on var.naming
  naming = {
    # Resource Groups
    # Pattern: rg-{workload}-{env}-{purpose}-{region_abbr}-{instance}
    resource_group_network    = { for region, abbr in local.get_region_abbr : region => "rg-${var.naming.workload}-${var.naming.env}-network-${abbr}-${var.naming.instance}" }
    resource_group_management = { for region, abbr in local.get_region_abbr : region => "rg-${var.naming.workload}-${var.naming.env}-mgmt-${abbr}-${var.naming.instance}" }

    # Virtual Networks
    # Pattern: vnet-{workload}-{env}-{region_abbr}-{instance}
    virtual_network = { for region, abbr in local.get_region_abbr : region => "vnet-${var.naming.workload}-${var.naming.env}-${abbr}-${var.naming.instance}" }

    # Route Tables
    # Pattern: rt-{workload}-{env}-{region_abbr}-{instance}
    route_table = { for region, abbr in local.get_region_abbr : region => "rt-${var.naming.workload}-${var.naming.env}-${abbr}-${var.naming.instance}" }

    # User Managed Identities
    # Pattern: id-{workload}-{env}-{region_abbr}-{instance}
    user_managed_identity = { for region, abbr in local.get_region_abbr : region => "id-${var.naming.workload}-${var.naming.env}-${abbr}-${var.naming.instance}" }

    # Recovery Services Vaults - Backup
    # Pattern: rsv-backup-{workload}-{env}-{region_abbr}-{instance}
    recovery_vault_backup = { for region, abbr in local.get_region_abbr : region => "rsv-backup-${var.naming.workload}-${var.naming.env}-${abbr}-${var.naming.instance}" }

    # Recovery Services Vaults - Site Recovery
    # Pattern: rsv-asr-{workload}-{env}-{region_abbr}-{instance}
    recovery_vault_asr = { for region, abbr in local.get_region_abbr : region => "rsv-asr-${var.naming.workload}-${var.naming.env}-${abbr}-${var.naming.instance}" }

    # Key Vault (name must be globally unique, 3-24 chars, alphanumeric only)
    # Pattern: kv{workload4}{region_abbr}{random4}{instance}
    # Example: kvidenuksabcd001 (16 chars)
    # Note: We use first 4 chars of workload to keep names concise
    # The random suffix is generated per region in terraform.tf
    key_vault_base = { for region, abbr in local.get_region_abbr : region => "kv${substr(var.naming.workload, 0, 4)}${abbr}" }

    # Subnet Names
    # Pattern: snet-{workload}-{env}-{purpose}-{region_abbr}-{instance}
    # Note: Purpose is passed in dynamically, so this is a helper function
    subnet = { for region, abbr in local.get_region_abbr : region => {
      prefix   = "snet-${var.naming.workload}-${var.naming.env}"
      suffix   = "${abbr}-${var.naming.instance}"
      region   = abbr
      instance = var.naming.instance
    }}

    # Hub Peering Names
    # Pattern: peer-{workload}-to-hub-{region_abbr}
    peering_to_hub = { for region, abbr in local.get_region_abbr : region => "peer-${var.naming.workload}-to-hub-${abbr}" }
    # Pattern: peer-hub-to-{workload}-{region_abbr}
    peering_from_hub = { for region, abbr in local.get_region_abbr : region => "peer-hub-to-${var.naming.workload}-${abbr}" }

    # vWAN Connection Names
    # Pattern: vhc-{workload}-{region_abbr}
    vwan_connection = { for region, abbr in local.get_region_abbr : region => "vhc-${var.naming.workload}-${abbr}" }

    # Virtual Machine Names
    # Pattern: vm-{workload}-{env}-{region_abbr}-{instance}
    virtual_machine = { for region, abbr in local.get_region_abbr : region => "vm-${var.naming.workload}-${var.naming.env}-${abbr}" }

    # VM NIC Names
    # Pattern: nic-{vm_name}
    vm_nic = { for region, abbr in local.get_region_abbr : region => "nic-${var.naming.workload}-${var.naming.env}-${abbr}" }

    # VM Resource Group Names
    # Pattern: rg-{workload}-{env}-compute-{region_abbr}-{instance}
    resource_group_compute = { for region, abbr in local.get_region_abbr : region => "rg-${var.naming.workload}-${var.naming.env}-compute-${abbr}-${var.naming.instance}" }
  }
}
