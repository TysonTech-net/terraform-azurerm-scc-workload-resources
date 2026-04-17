###############################################################################
# Variables - Compute (Virtual Machines)
###############################################################################

variable "compute_enabled" {
  type        = bool
  default     = true
  description = "Enable or disable deployment of compute resources (VMs). When false, no VMs will be deployed regardless of the compute variable contents."
}

variable "compute_auto_credential_keyvault_enabled" {
  type        = bool
  default     = true
  description = <<DESCRIPTION
When true and a regional Key Vault exists (deploy_management_key_vault = true),
the stack automatically:
  1. Sets generate_admin_password_or_ssh_key = true for VMs without an explicit admin_password
  2. Injects generated_secrets_key_vault_secret_config pointing to the regional Key Vault
  3. Grants the Terraform identity Key Vault Secrets Officer to write the generated secret

This removes the need for plaintext passwords in tfvars. VMs that explicitly set
admin_password bypass auto-generation and are not stored in Key Vault.
DESCRIPTION
}

variable "vm_admin_password" {
  type        = string
  sensitive   = true
  default     = null
  description = "Fallback admin password for VMs that don't set admin_password explicitly. Injected via TF_VAR_vm_admin_password from .env or CI secrets. When null, VMs without admin_password get auto-generated credentials stored in Key Vault."
}

variable "compute" {
  type = map(object({
    # Location defaults to the map key (region name) if not specified
    location = optional(string)

    # Telemetry
    enable_telemetry = optional(bool, true)

    # Tags
    tags = optional(map(string), {})

    # Log Analytics Workspace for diagnostics
    log_analytics_workspace_id = optional(string)

    # VM Resource Groups (optional - can use vending RGs instead)
    vm_resource_groups = optional(map(object({
      name     = optional(string)
      location = optional(string)
      tags     = optional(map(string))
    })), {})

    # Virtual Machines
    vms = optional(map(object({
      # Required
      name = string

      # Resource Group - either key reference or explicit name
      resource_group_key  = optional(string)
      resource_group_name = optional(string)

      # Location and Availability
      location = optional(string)
      zone     = optional(string)

      # VM Configuration
      os_type  = optional(string, "Windows")
      sku_size = optional(string, "Standard_D2s_v5")

      # Source Image - Gen2 compatible
      source_image_reference = optional(object({
        publisher = string
        offer     = string
        sku       = string
        version   = string
      }))
      source_image_resource_id = optional(string)

      # Marketplace Plan (required for marketplace images like Tenable, Palo Alto, etc.)
      plan = optional(object({
        name      = string
        product   = string
        publisher = string
      }))

      # OS Disk - defaults to Premium SSD with encryption
      os_disk = optional(object({
        caching                          = optional(string, "ReadWrite")
        storage_account_type             = optional(string, "Premium_LRS")
        disk_size_gb                     = optional(number)
        disk_encryption_set_id           = optional(string)
        name                             = optional(string)
        secure_vm_disk_encryption_set_id = optional(string)
        security_encryption_type         = optional(string)
        write_accelerator_enabled        = optional(bool, false)
      }))

      # Data Disks
      data_disk_managed_disks = optional(map(object({
        name                             = string
        storage_account_type             = optional(string, "Premium_LRS")
        lun                              = number
        caching                          = optional(string, "None")
        create_option                    = optional(string, "Empty")
        disk_size_gb                     = optional(number)
        disk_encryption_set_id           = optional(string)
        secure_vm_disk_encryption_set_id = optional(string)
        security_encryption_type         = optional(string)
        write_accelerator_enabled        = optional(bool, false)
      })))

      # Network Interfaces
      network_interfaces = map(object({
        name                           = optional(string)
        accelerated_networking_enabled = optional(bool, true)
        ip_forwarding_enabled          = optional(bool, false)
        dns_servers                    = optional(list(string))
        edge_zone                      = optional(string)
        internal_dns_name_label        = optional(string)
        tags                           = optional(map(string))

        ip_configurations = map(object({
          name                          = optional(string)
          private_ip_address            = optional(string)
          private_ip_address_allocation = optional(string, "Dynamic")
          private_ip_address_version    = optional(string, "IPv4")
          is_primary_ipconfiguration    = optional(bool, true)
          subnet_id                     = optional(string)
          # Reference subnet by key from vending config
          subnet_reference = optional(object({
            vnet_key   = string
            subnet_key = string
          }))
          public_ip_address_id = optional(string)
        }))
      }))

      # Authentication
      admin_username = optional(string, "azureadmin")
      admin_password = optional(string)
      # When unset (default true), any VM with an explicit or env-injected admin_password
      # automatically gets the password stored in the regional Key Vault for operational
      # retrieval. Set to false to opt a specific VM out of KV credential storage
      # (e.g. ephemeral dev VMs where credential retrieval isn't needed).
      store_password_in_keyvault         = optional(bool, true)
      generate_admin_password_or_ssh_key = optional(bool)

      # Telemetry
      enable_telemetry = optional(bool, true)

      # Managed Identity
      managed_identities = optional(object({
        system_assigned            = optional(bool, false)
        user_assigned_resource_ids = optional(set(string), [])
      }))

      # Security - Modern defaults for Gen2 VMs
      encryption_at_host_enabled = optional(bool, true)
      secure_boot_enabled        = optional(bool, true)
      vtpm_enabled               = optional(bool, true)

      # Patching
      patch_mode               = optional(string, "AutomaticByPlatform")
      patch_assessment_mode    = optional(string, "AutomaticByPlatform")
      enable_automatic_updates = optional(bool, true)
      # Required for AUM customer-managed schedules. Defaults to true via the
      # tag injection logic in main.compute.tf (every TF-managed VM is targeted
      # by AUM dynamic scopes via MaintenanceWindow tag). Set explicitly to
      # false to opt a VM out of AUM scheduling.
      bypass_platform_safety_checks_on_user_schedule_enabled = optional(bool)
      hotpatching_enabled                                    = optional(bool, false)

      # Boot Diagnostics
      boot_diagnostics                     = optional(bool, true)
      boot_diagnostics_storage_account_uri = optional(string)

      # Licensing
      license_type = optional(string)

      # Extensions
      extensions = optional(map(object({
        name                        = string
        publisher                   = string
        type                        = string
        type_handler_version        = string
        auto_upgrade_minor_version  = optional(bool, true)
        automatic_upgrade_enabled   = optional(bool, false)
        failure_suppression_enabled = optional(bool, false)
        settings                    = optional(string)
        protected_settings          = optional(string)
        provision_after_extensions  = optional(list(string))
        tags                        = optional(map(string))
      })))

      # Shutdown Schedule
      shutdown_schedules = optional(map(object({
        daily_recurrence_time = string
        timezone              = string
        notification_settings = optional(object({
          enabled         = optional(bool, false)
          email           = optional(string)
          time_in_minutes = optional(number, 30)
          webhook_url     = optional(string)
        }))
      })))

      # Backup
      azure_backup_configurations = optional(map(object({
        recovery_vault_resource_id = string
        backup_policy_resource_id  = string
      })))

      # Site Recovery (Azure Site Recovery / BCDR)
      # Enable ASR replication for this VM to the target region
      asr_enabled = optional(bool, false)
      asr = optional(object({
        enabled = optional(bool, false)

        # Target Resource Group (VM-level override)
        target_resource_group_key = optional(string) # Reference to vm_resource_groups key
        target_resource_group_id  = optional(string) # Direct RG ID (alternative)

        # Target Network (VM-level override)
        target_network_id  = optional(string) # Target VNet resource ID
        target_subnet_name = optional(string) # Subnet name in target VNet
        target_static_ip   = optional(string) # Static private IP in target

        # Target Availability (VM-level override)
        target_zone                         = optional(string) # Target availability zone
        target_availability_set_id          = optional(string)
        target_proximity_placement_group_id = optional(string)

        # Target Disk Configuration (VM-level override)
        target_disk_type              = optional(string) # e.g., "Premium_LRS", "StandardSSD_LRS"
        target_disk_encryption_set_id = optional(string)

        # Multi-VM Group for consistent recovery
        multi_vm_group_name = optional(string)
      }))

      # Maintenance Configuration (Azure Update Manager)
      # Recommended: Use maintenance_window tag for dynamic scoping
      # The VM will automatically be assigned to the maintenance window via dynamic scope
      # Valid values:
      #   - "patch_wave_1"          : OS-agnostic default wave (covers Windows + Linux)
      #   - "patch_wave_1_windows"  : Windows wave 1 (Wednesday after Patch Tuesday 22:00 GMT)
      #   - "patch_wave_2_windows"  : Windows wave 2 (Thursday after Patch Tuesday 22:00 GMT)
      #   - "patch_wave_1_linux"    : Linux wave 1 (Wednesday after Patch Tuesday 23:00 GMT)
      #   - "patch_wave_2_linux"    : Linux wave 2 (Thursday after Patch Tuesday 23:00 GMT)
      # If omitted, the Azure Policy Modify effect defaults the tag to "patch_wave_1".
      maintenance_window = optional(string)
      # Legacy Option 1: Reference central config by key (from platform_shared) - creates explicit assignment
      maintenance_configuration_key = optional(string)
      # Legacy Option 2: Specify resource IDs directly (for custom/external configs) - creates explicit assignment
      maintenance_configuration_resource_ids = optional(map(string))

      # SCC Management Tags (Logic Monitor collector-based monitoring flags)
      # - sccosmanagement = "true"    : VM is under SCC OS Boost/Management service (default for TF-managed VMs)
      # - sccnetworkmanagement = "true": VM is a network appliance under SCC Network Management
      # These tags drive Logic Monitor collector assignment rules. Defaults match
      # the typical SCC-managed infrastructure profile: OS management enabled,
      # network management disabled (network appliances must opt in explicitly).
      # VMs deployed outside Terraform get "false" for both via the Azure Policy
      # Modify effect defined in alz-mgmt (policy name: Add-Default-Tag-VM).
      sccosmanagement      = optional(string, "true")
      sccnetworkmanagement = optional(string, "false")

      # Backup Policy Selection
      # Drives per-VM backup policy via the BackupPolicy tag (tag name is
      # configurable via var.backup_policy_tag_name on the module). The
      # subscription-level Azure Policy assignments in this module (see
      # main.policy.backup.tf) deploy one DeployIfNotExists assignment per
      # (region, policy_name) combination, each scoped to VMs with the matching
      # tag value. Changing the tag re-registers the VM against the new policy
      # on the next policy evaluation.
      #
      # Tag value is the EXACT policy name as it exists in the vault (no
      # abstraction layer). For SCC defaults with CAF naming, this means
      # region-specific values like:
      #   - "pol-rsv-<workload>-<env>-basic-<region>-<instance>"     (30d daily)
      #   - "pol-rsv-<workload>-<env>-standard-<region>-<instance>"  (14d + 4w + 3m)
      #   - "pol-rsv-<workload>-<env>-extended-<region>-<instance>"  (14d + 4w + 12m + 7y)
      #
      # Examples (identity workload, prod, instance 001):
      #   uksouth basic    : "pol-rsv-identity-prod-basic-uks-001"
      #   ukwest standard  : "pol-rsv-identity-prod-standard-ukw-001"
      #
      # If unset, the per-region fallback assignment registers the VM against
      # the configured fallback policy (default: SCC basic tier for the region).
      # The Modify policy in alz-mgmt also defaults the BackupPolicy tag on
      # VMs created outside Terraform.
      backup_policy = optional(string)

      # Tags
      tags = optional(map(string), {})
    })), {})

    # Backup Defaults - applied to all VMs in this region
    backup_defaults = optional(object({
      recovery_vault_resource_id = string
      backup_policy_resource_id  = string
    }))

    # ASR Configuration - Region-level Site Recovery settings
    # When configured and VMs have asr.enabled = true, replication is set up
    asr_config = optional(object({
      # Target Region (required)
      target_location = string

      # Recovery Services Vault Configuration
      use_existing_vault        = optional(bool, false) # true = use existing, false = create new
      vault_name                = optional(string)      # RSV name (create or existing)
      vault_resource_group_name = optional(string)      # RG for vault (existing vault)
      vault_resource_group_key  = optional(string)      # Reference to vm_resource_groups

      # Replication Policy
      recovery_point_retention_in_minutes          = optional(number, 1440) # 24 hours
      app_consistent_snapshot_frequency_in_minutes = optional(number, 240)  # 4 hours

      # Target Network Defaults (for all VMs in this region)
      target_network_id             = optional(string) # Target VNet resource ID
      target_network_name           = optional(string) # Target VNet name (alternative to ID)
      target_network_resource_group = optional(string) # Target VNet resource group (required if using name)
      target_subnet_name            = optional(string) # Default subnet in target VNet

      # Target Resource Group Defaults (for replicated disks)
      target_resource_group_id   = optional(string)
      target_resource_group_name = optional(string)
      target_resource_group_key  = optional(string)

      # Capacity Reservation (optional)
      enable_capacity_reservation = optional(bool, false)
      capacity_reservation_sku    = optional(string)

      # Test Failover Network (optional)
      # Creates an isolated VNet with matching subnet names for DR drills.
      # No peering, no DNS, no routes. Subnets auto-divided as /28 blocks.
      create_test_network         = optional(bool, false)
      test_network_address_space  = optional(list(string), [])
      test_network_subnet_newbits = optional(number, 4)

      # Automation Account for ASR agent auto-update (optional, cross-sub supported)
      automation_account_id = optional(string)
    }))
  }))
  default     = {}
  description = <<DESCRIPTION
A map of compute configurations keyed by region.

Each key represents a region (e.g., "uksouth", "ukwest") and the value contains all the configuration
for deploying virtual machines in that region, including VM definitions, resource groups, and backup settings.

VMs are configured with modern security defaults:
- Gen2 compatible images
- Encryption at host enabled
- Secure Boot enabled
- vTPM enabled
- Premium SSD OS disks
- Accelerated networking

Example:
```hcl
compute = {
  uksouth = {
    location = "uksouth"
    vms = {
      dc01 = {
        name               = "vm-dc-uks-001"
        resource_group_key = "management"
        zone               = "1"
        sku_size           = "Standard_D2s_v5"
        source_image_reference = {
          publisher = "MicrosoftWindowsServer"
          offer     = "WindowsServer"
          sku       = "2022-datacenter-azure-edition-smalldisk"
          version   = "latest"
        }
        network_interfaces = {
          primary = {
            ip_configurations = {
              ipconfig1 = {
                subnet_reference = {
                  vnet_key   = "identity"
                  subnet_key = "domain_controllers"
                }
              }
            }
          }
        }
      }
    }
  }
}
```
DESCRIPTION
}
