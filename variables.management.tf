variable "management" {
  type = map(object({
    location         = string
    tags             = optional(map(string), {})
    enable_telemetry = optional(bool, true)

    # Resource Group
    use_existing_management_resource_group = optional(bool, false)
    management_resource_group_name         = optional(string, "")
    management_resource_group_lock = optional(object({
      kind = string
      name = optional(string, null)
    }), null)
    management_resource_group_role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})

    # Backup Recovery Services Vault
    deploy_management_backup_recovery_services_vault                     = optional(bool, true)
    management_backup_rsv_name                                           = string
    management_backup_rsv_sku                                            = optional(string, "Standard")
    management_backup_rsv_alerts_for_all_job_failures_enabled            = optional(bool, true)
    management_backup_rsv_alerts_for_critical_operation_failures_enabled = optional(bool, true)
    management_backup_rsv_backup_protected_file_share = optional(map(object({
      source_storage_account_id     = string
      backup_file_share_policy_name = string
      source_file_share_name        = string
      disable_registration          = optional(bool, false)
      sleep_timer                   = optional(string, "60s")
    })), null)
    management_backup_rsv_backup_protected_vm = optional(map(object({
      source_vm_id          = string
      vm_backup_policy_name = string
      sleep_timer           = optional(string, "60s")
    })), null)
    management_backup_rsv_classic_vmware_replication_enabled = optional(bool, false)
    management_backup_rsv_cross_region_restore_enabled       = optional(bool, true)
    management_backup_rsv_customer_managed_key = optional(object({
      key_vault_resource_id = string
      key_name              = string
      key_version           = optional(string, null)
      user_assigned_identity = optional(object({
        resource_id = string
      }), null)
    }), null)
    management_backup_rsv_diagnostic_settings = optional(map(object({
      name                                     = optional(string, null)
      log_categories                           = optional(set(string), [])
      log_groups                               = optional(set(string), ["allLogs"])
      metric_categories                        = optional(set(string), ["AllMetrics"])
      log_analytics_destination_type           = optional(string, "Dedicated")
      workspace_resource_id                    = optional(string, null)
      storage_account_resource_id              = optional(string, null)
      event_hub_authorization_rule_resource_id = optional(string, null)
      event_hub_name                           = optional(string, null)
      marketplace_partner_resource_id          = optional(string, null)
    })), {})
    management_backup_rsv_enable_telemetry = optional(bool, true)
    management_backup_rsv_file_share_backup_policy = optional(map(object({
      name            = string
      timezone        = string
      frequency       = string
      retention_daily = optional(number, null)
      backup = object({
        time = string
        hourly = optional(object({
          interval        = number
          start_time      = string
          window_duration = number
        }))
      })
      retention_weekly = optional(object({
        count    = optional(number, 7)
        weekdays = optional(list(string), [])
      }), {})
      retention_monthly = optional(object({
        count             = optional(number, 0)
        weekdays          = optional(list(string), [])
        weeks             = optional(list(string), [])
        days              = optional(list(number), [])
        include_last_days = optional(bool, false)
      }), {})
      retention_yearly = optional(object({
        count             = optional(number, 0)
        months            = optional(list(string), [])
        weekdays          = optional(list(string), [])
        weeks             = optional(list(string), [])
        days              = optional(list(number), [])
        include_last_days = optional(bool, false)
      }), {})
    })), null)
    management_backup_rsv_immutability = optional(string, "Unlocked")
    management_backup_rsv_lock = optional(object({
      name = optional(string, null)
      kind = string
    }), null)
    management_backup_rsv_managed_identities = optional(object({
      system_assigned            = optional(bool, false)
      user_assigned_resource_ids = optional(set(string), [])
    }), {})
    management_backup_rsv_private_endpoints = optional(map(object({
      name = optional(string, null)
      role_assignments = optional(map(object({
        role_definition_id_or_name             = string
        principal_id                           = string
        description                            = optional(string, null)
        skip_service_principal_aad_check       = optional(bool, false)
        condition                              = optional(string, null)
        condition_version                      = optional(string, null)
        delegated_managed_identity_resource_id = optional(string, null)
        principal_type                         = optional(string, null)
      })), {})
      lock = optional(object({
        kind = string
        name = optional(string, null)
      }), null)
      tags                                    = optional(map(string), null)
      subnet_resource_id                      = string
      subresource_name                        = optional(string, "AzureBackup")
      private_dns_zone_group_name             = optional(string, "default")
      private_dns_zone_resource_ids           = optional(set(string), [])
      application_security_group_associations = optional(map(string), {})
      private_service_connection_name         = optional(string, null)
      network_interface_name                  = optional(string, null)
      location                                = optional(string, null)
      resource_group_name                     = optional(string, null)
      ip_configurations = optional(map(object({
        name               = string
        private_ip_address = string
      })), {})
    })), {})
    management_backup_rsv_private_endpoints_manage_dns_zone_group = optional(bool, true)
    management_backup_rsv_public_network_access_enabled           = optional(bool, true)
    management_backup_rsv_role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    management_backup_rsv_soft_delete_enabled = optional(bool, true)
    management_backup_rsv_storage_mode_type   = optional(string, "GeoRedundant")
    management_backup_rsv_tags                = optional(map(string), null)
    management_backup_rsv_vm_backup_policy = optional(map(object({
      name                           = string
      timezone                       = string
      instant_restore_retention_days = optional(number, null)
      instant_restore_resource_group = optional(map(object({
        prefix = optional(string, null)
        suffix = optional(string, null)
      })), {})
      policy_type     = string
      frequency       = string
      retention_daily = optional(number, null)
      backup = object({
        time          = string
        hour_interval = optional(number, null)
        hour_duration = optional(number, null)
        weekdays      = optional(list(string), [])
      })
      retention_weekly = optional(object({
        count    = optional(number, 7)
        weekdays = optional(list(string), [])
      }), {})
      retention_monthly = optional(object({
        count             = optional(number, 0)
        weekdays          = optional(list(string), [])
        weeks             = optional(list(string), [])
        days              = optional(list(number), [])
        include_last_days = optional(bool, false)
      }), {})
      retention_yearly = optional(object({
        count             = optional(number, 0)
        months            = optional(list(string), [])
        weekdays          = optional(list(string), [])
        weeks             = optional(list(string), [])
        days              = optional(list(number), [])
        include_last_days = optional(bool, false)
      }), {})
    })), null)
    management_backup_rsv_workload_backup_policy = optional(map(object({
      name          = string
      workload_type = string
      settings = object({
        time_zone           = string
        compression_enabled = bool
      })
      backup_frequency = string
      protection_policy = map(object({
        policy_type           = string
        retention_daily_count = number
        retention_weekly = optional(object({
          count    = optional(number, null)
          weekdays = optional(set(string), null)
        }), null)
        backup = optional(object({
          time                 = optional(string)
          frequency_in_minutes = optional(number)
          weekdays             = optional(set(string))
        }), null)
        retention_monthly = optional(object({
          count             = optional(number, null)
          weekdays          = optional(set(string), null)
          weeks             = optional(set(string), null)
          monthdays         = optional(set(number), null)
          include_last_days = optional(bool, false)
        }), null)
        retention_yearly = optional(object({
          count             = optional(number, null)
          months            = optional(set(string), null)
          weekdays          = optional(set(string), null)
          weeks             = optional(set(string), null)
          monthdays         = optional(set(number), null)
          include_last_days = optional(bool, false)
        }), null)
      }))
    })), null)

    # Site Recovery Recovery Services Vault
    deploy_management_site_recovery_recovery_services_vault                     = optional(bool, true)
    management_site_recovery_rsv_name                                           = string
    management_site_recovery_rsv_sku                                            = optional(string, "Standard")
    management_site_recovery_rsv_alerts_for_all_job_failures_enabled            = optional(bool, true)
    management_site_recovery_rsv_alerts_for_critical_operation_failures_enabled = optional(bool, true)
    management_site_recovery_rsv_classic_vmware_replication_enabled             = optional(bool, false)
    management_site_recovery_rsv_cross_region_restore_enabled                   = optional(bool, false)
    management_site_recovery_rsv_customer_managed_key = optional(object({
      key_vault_resource_id = string
      key_name              = string
      key_version           = optional(string, null)
      user_assigned_identity = optional(object({
        resource_id = string
      }), null)
    }), null)
    management_site_recovery_rsv_diagnostic_settings = optional(map(object({
      name                                     = optional(string, null)
      log_categories                           = optional(set(string), [])
      log_groups                               = optional(set(string), ["allLogs"])
      metric_categories                        = optional(set(string), ["AllMetrics"])
      log_analytics_destination_type           = optional(string, "Dedicated")
      workspace_resource_id                    = optional(string, null)
      storage_account_resource_id              = optional(string, null)
      event_hub_authorization_rule_resource_id = optional(string, null)
      event_hub_name                           = optional(string, null)
      marketplace_partner_resource_id          = optional(string, null)
    })), {})
    management_site_recovery_rsv_enable_telemetry = optional(bool, true)
    management_site_recovery_rsv_immutability     = optional(string, "Unlocked")
    management_site_recovery_rsv_lock = optional(object({
      name = optional(string, null)
      kind = string
    }), null)
    management_site_recovery_rsv_managed_identities = optional(object({
      system_assigned            = optional(bool, false)
      user_assigned_resource_ids = optional(set(string), [])
    }), {})
    management_site_recovery_rsv_private_endpoints = optional(map(object({
      name = optional(string, null)
      role_assignments = optional(map(object({
        role_definition_id_or_name             = string
        principal_id                           = string
        description                            = optional(string, null)
        skip_service_principal_aad_check       = optional(bool, false)
        condition                              = optional(string, null)
        condition_version                      = optional(string, null)
        delegated_managed_identity_resource_id = optional(string, null)
        principal_type                         = optional(string, null)
      })), {})
      lock = optional(object({
        kind = string
        name = optional(string, null)
      }), null)
      tags                                    = optional(map(string), null)
      subnet_resource_id                      = string
      subresource_name                        = optional(string, "AzureSiteRecovery")
      private_dns_zone_group_name             = optional(string, "default")
      private_dns_zone_resource_ids           = optional(set(string), [])
      application_security_group_associations = optional(map(string), {})
      private_service_connection_name         = optional(string, null)
      network_interface_name                  = optional(string, null)
      location                                = optional(string, null)
      resource_group_name                     = optional(string, null)
      ip_configurations = optional(map(object({
        name               = string
        private_ip_address = string
      })), {})
    })), {})
    management_site_recovery_rsv_private_endpoints_manage_dns_zone_group = optional(bool, true)
    management_site_recovery_rsv_public_network_access_enabled           = optional(bool, true)
    management_site_recovery_rsv_role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    management_site_recovery_rsv_soft_delete_enabled = optional(bool, true)
    management_site_recovery_rsv_storage_mode_type   = optional(string, "LocallyRedundant")
    management_site_recovery_rsv_tags                = optional(map(string), null)

    # Key Vault
    deploy_management_key_vault                   = optional(bool, true)
    management_kv_name                            = string
    management_kv_tenant_id                       = string
    management_kv_tags                            = optional(map(string), null)
    management_kv_enable_telemetry                = optional(bool, true)
    management_kv_sku_name                        = optional(string, "premium")
    management_kv_soft_delete_retention_days      = optional(number, null)
    management_kv_purge_protection_enabled        = optional(bool, true)
    management_kv_enabled_for_deployment          = optional(bool, false)
    management_kv_enabled_for_disk_encryption     = optional(bool, false)
    management_kv_enabled_for_template_deployment = optional(bool, false)
    management_kv_legacy_access_policies_enabled  = optional(bool, false)
    management_kv_legacy_access_policies = optional(map(object({
      object_id               = string
      application_id          = optional(string, null)
      certificate_permissions = optional(set(string), [])
      key_permissions         = optional(set(string), [])
      secret_permissions      = optional(set(string), [])
      storage_permissions     = optional(set(string), [])
    })), {})
    management_kv_public_network_access_enabled = optional(bool, true)
    management_kv_network_acls = optional(object({
      bypass                     = optional(string, "None")
      default_action             = optional(string, "Deny")
      ip_rules                   = optional(list(string), [])
      virtual_network_subnet_ids = optional(list(string), [])
    }), {})
    management_kv_private_endpoints = optional(map(object({
      name = optional(string, null)
      role_assignments = optional(map(object({
        role_definition_id_or_name             = string
        principal_id                           = string
        description                            = optional(string, null)
        skip_service_principal_aad_check       = optional(bool, false)
        condition                              = optional(string, null)
        condition_version                      = optional(string, null)
        delegated_managed_identity_resource_id = optional(string, null)
        principal_type                         = optional(string, null)
      })), {})
      lock = optional(object({
        kind = string
        name = optional(string, null)
      }), null)
      tags                                    = optional(map(string), null)
      subnet_resource_id                      = string
      private_dns_zone_group_name             = optional(string, "default")
      private_dns_zone_resource_ids           = optional(set(string), [])
      application_security_group_associations = optional(map(string), {})
      private_service_connection_name         = optional(string, null)
      network_interface_name                  = optional(string, null)
      location                                = optional(string, null)
      resource_group_name                     = optional(string, null)
      ip_configurations = optional(map(object({
        name               = string
        private_ip_address = string
      })), {})
    })), {})
    management_kv_private_endpoints_manage_dns_zone_group = optional(bool, true)
    management_kv_role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    management_kv_lock = optional(object({
      kind = string
      name = optional(string, null)
    }), null)
    management_kv_contacts = optional(map(object({
      email = string
      name  = optional(string, null)
      phone = optional(string, null)
    })), {})
    management_kv_diagnostic_settings = optional(map(object({
      name                                     = optional(string, null)
      log_categories                           = optional(set(string), [])
      log_groups                               = optional(set(string), ["allLogs"])
      metric_categories                        = optional(set(string), ["AllMetrics"])
      log_analytics_destination_type           = optional(string, "Dedicated")
      workspace_resource_id                    = optional(string, null)
      storage_account_resource_id              = optional(string, null)
      event_hub_authorization_rule_resource_id = optional(string, null)
      event_hub_name                           = optional(string, null)
      marketplace_partner_resource_id          = optional(string, null)
    })), {})
    management_kv_keys = optional(map(object({
      name            = string
      key_type        = string
      key_opts        = optional(list(string), ["sign", "verify"])
      key_size        = optional(number, null)
      curve           = optional(string, null)
      not_before_date = optional(string, null)
      expiration_date = optional(string, null)
      tags            = optional(map(any), null)
      role_assignments = optional(map(object({
        role_definition_id_or_name             = string
        principal_id                           = string
        description                            = optional(string, null)
        skip_service_principal_aad_check       = optional(bool, false)
        condition                              = optional(string, null)
        condition_version                      = optional(string, null)
        delegated_managed_identity_resource_id = optional(string, null)
        principal_type                         = optional(string, null)
      })), {})
      rotation_policy = optional(object({
        automatic = optional(object({
          time_after_creation = optional(string, null)
          time_before_expiry  = optional(string, null)
        }), null)
        expire_after         = optional(string, null)
        notify_before_expiry = optional(string, null)
      }), null)
    })), {})
    management_kv_secrets = optional(map(object({
      name            = string
      content_type    = optional(string, null)
      tags            = optional(map(any), null)
      not_before_date = optional(string, null)
      expiration_date = optional(string, null)
      role_assignments = optional(map(object({
        role_definition_id_or_name             = string
        principal_id                           = string
        description                            = optional(string, null)
        skip_service_principal_aad_check       = optional(bool, false)
        condition                              = optional(string, null)
        condition_version                      = optional(string, null)
        delegated_managed_identity_resource_id = optional(string, null)
        principal_type                         = optional(string, null)
      })), {})
    })), {})
    management_kv_secrets_value = optional(map(string), null)
    management_kv_wait_for_rbac_before_key_operations = optional(object({
      create  = optional(string, "30s")
      destroy = optional(string, "0s")
    }), {})
    management_kv_wait_for_rbac_before_secret_operations = optional(object({
      create  = optional(string, "30s")
      destroy = optional(string, "0s")
    }), {})
    management_kv_wait_for_rbac_before_contact_operations = optional(object({
      create  = optional(string, "30s")
      destroy = optional(string, "0s")
    }), {})
  }))
  default     = {}
  description = <<DESCRIPTION
A map of workload management configurations keyed by region.

Each key represents a region (e.g., "uksouth", "ukwest") and the value contains all the configuration
for management resources in that region, including resource groups, backup recovery services vaults,
site recovery vaults, and key vaults.

Example:
```hcl
management = {
  uksouth = {
    location                              = "uksouth"
    management_resource_group_name        = "rg-mgmt-identity-uks"
    management_backup_rsv_name            = "rsv-backup-identity-uks"
    management_site_recovery_rsv_name     = "rsv-asr-identity-uks"
    management_kv_name                    = "kv-identity-uks"
    management_kv_tenant_id               = "00000000-0000-0000-0000-000000000000"
  }
  ukwest = {
    location                              = "ukwest"
    management_resource_group_name        = "rg-mgmt-identity-ukw"
    management_backup_rsv_name            = "rsv-backup-identity-ukw"
    management_site_recovery_rsv_name     = "rsv-asr-identity-ukw"
    management_kv_name                    = "kv-identity-ukw"
    management_kv_tenant_id               = "00000000-0000-0000-0000-000000000000"
  }
}
```
DESCRIPTION
}
