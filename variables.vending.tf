variable "vending" {
  type = map(object({
    location = string

    # Telemetry
    disable_telemetry = optional(bool, false)

    # Resource Providers
    subscription_register_resource_providers_enabled      = optional(bool, false)
    subscription_register_resource_providers_and_features = optional(map(set(string)), {})

    # Resource Groups
    resource_group_creation_enabled = optional(bool, false)
    resource_groups = optional(map(object({
      name         = string
      location     = optional(string)
      tags         = optional(map(string), {})
      lock_enabled = optional(bool, false)
      lock_name    = optional(string, "")
    })), {})

    # Virtual Networks
    virtual_network_enabled = optional(bool, false)
    virtual_networks = optional(map(object({
      name                         = string
      address_space                = list(string)
      resource_group_key           = optional(string)
      resource_group_name_existing = optional(string)

      location = optional(string)

      dns_servers             = optional(list(string), [])
      flow_timeout_in_minutes = optional(number)

      ddos_protection_enabled = optional(bool, false)
      ddos_protection_plan_id = optional(string)

      subnets = optional(map(object({
        name             = string
        address_prefixes = list(string)
        nat_gateway = optional(object({
          id = string
        }))
        network_security_group = optional(object({
          id            = optional(string)
          key_reference = optional(string)
        }))
        private_endpoint_network_policies             = optional(string, "Enabled")
        private_link_service_network_policies_enabled = optional(bool, true)
        route_table = optional(object({
          id            = optional(string)
          key_reference = optional(string)
        }))
        default_outbound_access_enabled = optional(bool, false)
        service_endpoints               = optional(set(string))
        service_endpoint_policies = optional(map(object({
          id = string
        })))
        delegations = optional(list(object({
          name = string
          service_delegation = object({
            name = string
          })
        })))
      })), {})

      hub_network_resource_id = optional(string)
      hub_peering_enabled     = optional(bool, false)
      hub_peering_direction   = optional(string, "both")
      hub_peering_name_tohub  = optional(string)
      hub_peering_options_tohub = optional(object({
        allow_forwarded_traffic       = optional(bool, true)
        allow_gateway_transit         = optional(bool, false)
        allow_virtual_network_access  = optional(bool, true)
        do_not_verify_remote_gateways = optional(bool, false)
        enable_only_ipv6_peering      = optional(bool, false)
        local_peered_address_spaces   = optional(list(string), [])
        local_peered_subnets          = optional(list(string), [])
        peer_complete_vnets           = optional(bool, true)
        remote_peered_address_spaces  = optional(list(string), [])
        remote_peered_subnets         = optional(list(string), [])
        use_remote_gateways           = optional(bool, true)
      }), {})
      hub_peering_name_fromhub = optional(string)
      hub_peering_options_fromhub = optional(object({
        allow_forwarded_traffic       = optional(bool, true)
        allow_gateway_transit         = optional(bool, true)
        allow_virtual_network_access  = optional(bool, true)
        do_not_verify_remote_gateways = optional(bool, false)
        enable_only_ipv6_peering      = optional(bool, false)
        local_peered_address_spaces   = optional(list(string), [])
        local_peered_subnets          = optional(list(string), [])
        peer_complete_vnets           = optional(bool, true)
        remote_peered_address_spaces  = optional(list(string), [])
        remote_peered_subnets         = optional(list(string), [])
        use_remote_gateways           = optional(bool, false)
      }), {})

      mesh_peering_enabled                 = optional(bool, false)
      mesh_peering_allow_forwarded_traffic = optional(bool, false)

      vwan_associated_routetable_resource_id   = optional(string)
      vwan_connection_enabled                  = optional(bool, false)
      vwan_connection_name                     = optional(string)
      vwan_hub_resource_id                     = optional(string)
      vwan_propagated_routetables_labels       = optional(list(string), [])
      vwan_propagated_routetables_resource_ids = optional(list(string), [])
      vwan_security_configuration = optional(object({
        secure_internet_traffic = optional(bool, false)
        secure_private_traffic  = optional(bool, false)
        routing_intent_enabled  = optional(bool, false)
      }), {})

      tags = optional(map(string), {})
    })), {})

    # Role Assignments
    role_assignment_enabled = optional(bool, false)
    role_assignments = optional(map(object({
      principal_id              = string
      definition                = string
      relative_scope            = optional(string, "")
      resource_group_scope_key  = optional(string)
      condition                 = optional(string)
      condition_version         = optional(string)
      principal_type            = optional(string)
      definition_lookup_enabled = optional(bool, false)
      use_random_uuid           = optional(bool, false)
    })), {})

    # User Managed Identities
    umi_enabled = optional(bool, false)
    user_managed_identities = optional(map(object({
      name                         = string
      resource_group_key           = optional(string)
      resource_group_name_existing = optional(string)
      location                     = optional(string)
      tags                         = optional(map(string), {})
      role_assignments = optional(map(object({
        definition                = string
        relative_scope            = optional(string, "")
        resource_group_scope_key  = optional(string)
        condition                 = optional(string)
        condition_version         = optional(string)
        principal_type            = optional(string)
        definition_lookup_enabled = optional(bool, false)
        use_random_uuid           = optional(bool, false)
      })), {})
      federated_credentials_github = optional(map(object({
        name            = optional(string)
        organization    = string
        repository      = string
        entity          = string
        enterprise_slug = optional(string)
        value           = optional(string)
      })), {})
      federated_credentials_terraform_cloud = optional(map(object({
        name         = optional(string)
        organization = string
        project      = string
        workspace    = string
        run_phase    = string
      })), {})
      federated_credentials_advanced = optional(map(object({
        name               = string
        subject_identifier = string
        issuer_url         = string
        audiences          = optional(set(string), ["api://AzureADTokenExchange"])
      })), {})
    })), {})

    # Budgets
    budget_enabled = optional(bool, false)
    budgets = optional(map(object({
      name               = string
      amount             = number
      time_grain         = string
      time_period_start  = string
      time_period_end    = string
      relative_scope     = optional(string, "")
      resource_group_key = optional(string)
      notifications = optional(map(object({
        enabled        = bool
        operator       = string
        threshold      = number
        threshold_type = optional(string, "Actual")
        contact_emails = optional(list(string), [])
        contact_roles  = optional(list(string), [])
        contact_groups = optional(list(string), [])
        locale         = optional(string, "en-us")
      })), {})
    })), {})

    # Route Tables
    route_table_enabled = optional(bool, false)
    route_tables = optional(map(object({
      name                          = string
      location                      = string
      resource_group_key            = optional(string)
      resource_group_name_existing  = optional(string)
      bgp_route_propagation_enabled = optional(bool, true)
      tags                          = optional(map(string))

      routes = optional(map(object({
        name                   = string
        address_prefix         = string
        next_hop_type          = string
        next_hop_in_ip_address = optional(string)
      })), {})
    })), {})

    # Network Security Groups
    network_security_group_enabled = optional(bool, false)
    network_security_groups = optional(map(object({
      name                         = string
      location                     = optional(string)
      resource_group_key           = optional(string)
      resource_group_name_existing = optional(string)
      tags                         = optional(map(string))

      security_rules = optional(map(object({
        access                                     = string
        description                                = optional(string)
        destination_address_prefix                 = optional(string)
        destination_address_prefixes               = optional(set(string))
        destination_application_security_group_ids = optional(set(string))
        destination_port_range                     = optional(string)
        destination_port_ranges                    = optional(set(string))
        direction                                  = string
        name                                       = string
        priority                                   = number
        protocol                                   = string
        source_address_prefix                      = optional(string)
        source_address_prefixes                    = optional(set(string))
        source_application_security_group_ids      = optional(set(string))
        source_port_range                          = optional(string)
        source_port_ranges                         = optional(set(string))
      })))
    })), {})

    # Wait Timer
    wait_for_subscription_before_subscription_operations = optional(object({
      create  = optional(string, "30s")
      destroy = optional(string, "0s")
    }), {})
  }))
  default     = {}
  description = <<DESCRIPTION
A map of subscription vending configurations keyed by region.

Each key represents a region (e.g., "uksouth", "ukwest") and the value contains all the configuration
for vending resources in that region, including virtual networks, resource groups, role assignments,
user managed identities, budgets, route tables, and network security groups.

Example:
```hcl
vending = {
  uksouth = {
    location = "uksouth"
    virtual_network_enabled = true
    virtual_networks = {
      identity = {
        name          = "vnet-identity-uks"
        address_space = ["10.0.0.0/24"]
        # ...
      }
    }
  }
  ukwest = {
    location = "ukwest"
    virtual_network_enabled = true
    virtual_networks = {
      identity = {
        name          = "vnet-identity-ukw"
        address_space = ["10.1.0.0/24"]
        # ...
      }
    }
  }
}
```
DESCRIPTION
}
