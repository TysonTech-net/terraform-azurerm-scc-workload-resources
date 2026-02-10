module "workload_management" {
  source   = "../../alz-modules/modules/scc-azure-workload-management"
  for_each = var.management

  # Shared
  location         = each.value.location
  tags             = each.value.tags
  enable_telemetry = each.value.enable_telemetry

  # Resource Group
  use_existing_management_resource_group     = each.value.use_existing_management_resource_group
  management_resource_group_name             = each.value.management_resource_group_name
  management_resource_group_lock             = each.value.management_resource_group_lock
  management_resource_group_role_assignments = each.value.management_resource_group_role_assignments

  # Backup Recovery Services Vault
  deploy_management_backup_recovery_services_vault                     = each.value.deploy_management_backup_recovery_services_vault
  management_backup_rsv_name                                           = each.value.management_backup_rsv_name
  management_backup_rsv_sku                                            = each.value.management_backup_rsv_sku
  management_backup_rsv_alerts_for_all_job_failures_enabled            = each.value.management_backup_rsv_alerts_for_all_job_failures_enabled
  management_backup_rsv_alerts_for_critical_operation_failures_enabled = each.value.management_backup_rsv_alerts_for_critical_operation_failures_enabled
  management_backup_rsv_backup_protected_file_share                    = each.value.management_backup_rsv_backup_protected_file_share
  management_backup_rsv_backup_protected_vm                            = each.value.management_backup_rsv_backup_protected_vm
  management_backup_rsv_classic_vmware_replication_enabled             = each.value.management_backup_rsv_classic_vmware_replication_enabled
  management_backup_rsv_cross_region_restore_enabled                   = each.value.management_backup_rsv_cross_region_restore_enabled
  management_backup_rsv_customer_managed_key                           = each.value.management_backup_rsv_customer_managed_key
  management_backup_rsv_diagnostic_settings                            = each.value.management_backup_rsv_diagnostic_settings
  management_backup_rsv_enable_telemetry                               = each.value.management_backup_rsv_enable_telemetry
  management_backup_rsv_file_share_backup_policy                       = each.value.management_backup_rsv_file_share_backup_policy
  management_backup_rsv_immutability                                   = each.value.management_backup_rsv_immutability
  management_backup_rsv_lock                                           = each.value.management_backup_rsv_lock
  management_backup_rsv_managed_identities                             = each.value.management_backup_rsv_managed_identities
  management_backup_rsv_private_endpoints                              = each.value.management_backup_rsv_private_endpoints
  management_backup_rsv_private_endpoints_manage_dns_zone_group        = each.value.management_backup_rsv_private_endpoints_manage_dns_zone_group
  management_backup_rsv_public_network_access_enabled                  = each.value.management_backup_rsv_public_network_access_enabled
  management_backup_rsv_role_assignments                               = each.value.management_backup_rsv_role_assignments
  management_backup_rsv_soft_delete_enabled                            = each.value.management_backup_rsv_soft_delete_enabled
  management_backup_rsv_storage_mode_type                              = each.value.management_backup_rsv_storage_mode_type
  management_backup_rsv_tags                                           = each.value.management_backup_rsv_tags
  management_backup_rsv_vm_backup_policy                               = each.value.management_backup_rsv_vm_backup_policy
  management_backup_rsv_workload_backup_policy                         = each.value.management_backup_rsv_workload_backup_policy

  # Site Recovery Recovery Services Vault
  deploy_management_site_recovery_recovery_services_vault                     = each.value.deploy_management_site_recovery_recovery_services_vault
  management_site_recovery_rsv_name                                           = each.value.management_site_recovery_rsv_name
  management_site_recovery_rsv_sku                                            = each.value.management_site_recovery_rsv_sku
  management_site_recovery_rsv_alerts_for_all_job_failures_enabled            = each.value.management_site_recovery_rsv_alerts_for_all_job_failures_enabled
  management_site_recovery_rsv_alerts_for_critical_operation_failures_enabled = each.value.management_site_recovery_rsv_alerts_for_critical_operation_failures_enabled
  management_site_recovery_rsv_classic_vmware_replication_enabled             = each.value.management_site_recovery_rsv_classic_vmware_replication_enabled
  management_site_recovery_rsv_cross_region_restore_enabled                   = each.value.management_site_recovery_rsv_cross_region_restore_enabled
  management_site_recovery_rsv_customer_managed_key                           = each.value.management_site_recovery_rsv_customer_managed_key
  management_site_recovery_rsv_diagnostic_settings                            = each.value.management_site_recovery_rsv_diagnostic_settings
  management_site_recovery_rsv_enable_telemetry                               = each.value.management_site_recovery_rsv_enable_telemetry
  management_site_recovery_rsv_immutability                                   = each.value.management_site_recovery_rsv_immutability
  management_site_recovery_rsv_lock                                           = each.value.management_site_recovery_rsv_lock
  management_site_recovery_rsv_managed_identities                             = each.value.management_site_recovery_rsv_managed_identities
  management_site_recovery_rsv_private_endpoints                              = each.value.management_site_recovery_rsv_private_endpoints
  management_site_recovery_rsv_private_endpoints_manage_dns_zone_group        = each.value.management_site_recovery_rsv_private_endpoints_manage_dns_zone_group
  management_site_recovery_rsv_public_network_access_enabled                  = each.value.management_site_recovery_rsv_public_network_access_enabled
  management_site_recovery_rsv_role_assignments                               = each.value.management_site_recovery_rsv_role_assignments
  management_site_recovery_rsv_soft_delete_enabled                            = each.value.management_site_recovery_rsv_soft_delete_enabled
  management_site_recovery_rsv_storage_mode_type                              = each.value.management_site_recovery_rsv_storage_mode_type
  management_site_recovery_rsv_tags                                           = each.value.management_site_recovery_rsv_tags

  # Key Vault
  deploy_management_key_vault                           = each.value.deploy_management_key_vault
  management_kv_name                                    = each.value.management_kv_name
  management_kv_tenant_id                               = each.value.management_kv_tenant_id
  management_kv_tags                                    = each.value.management_kv_tags
  management_kv_enable_telemetry                        = each.value.management_kv_enable_telemetry
  management_kv_sku_name                                = each.value.management_kv_sku_name
  management_kv_soft_delete_retention_days              = each.value.management_kv_soft_delete_retention_days
  management_kv_purge_protection_enabled                = each.value.management_kv_purge_protection_enabled
  management_kv_enabled_for_deployment                  = each.value.management_kv_enabled_for_deployment
  management_kv_enabled_for_disk_encryption             = each.value.management_kv_enabled_for_disk_encryption
  management_kv_enabled_for_template_deployment         = each.value.management_kv_enabled_for_template_deployment
  management_kv_legacy_access_policies_enabled          = each.value.management_kv_legacy_access_policies_enabled
  management_kv_legacy_access_policies                  = each.value.management_kv_legacy_access_policies
  management_kv_public_network_access_enabled           = each.value.management_kv_public_network_access_enabled
  management_kv_network_acls                            = each.value.management_kv_network_acls
  management_kv_private_endpoints                       = each.value.management_kv_private_endpoints
  management_kv_private_endpoints_manage_dns_zone_group = each.value.management_kv_private_endpoints_manage_dns_zone_group
  management_kv_role_assignments                        = each.value.management_kv_role_assignments
  management_kv_lock                                    = each.value.management_kv_lock
  management_kv_contacts                                = each.value.management_kv_contacts
  management_kv_diagnostic_settings                     = each.value.management_kv_diagnostic_settings
  management_kv_keys                                    = each.value.management_kv_keys
  management_kv_secrets                                 = each.value.management_kv_secrets
  management_kv_secrets_value                           = each.value.management_kv_secrets_value
  management_kv_wait_for_rbac_before_key_operations     = each.value.management_kv_wait_for_rbac_before_key_operations
  management_kv_wait_for_rbac_before_secret_operations  = each.value.management_kv_wait_for_rbac_before_secret_operations
  management_kv_wait_for_rbac_before_contact_operations = each.value.management_kv_wait_for_rbac_before_contact_operations
}
