# terraform-azurerm-scc-workload-resources

Multi-region workload vending stack for Azure Landing Zones. Orchestrates subscription vending, workload management, and compute deployment.

## Usage

```hcl
module "workload_resources" {
  source = "git::https://github.com/TysonTech-net/terraform-azurerm-scc-workload-resources.git?ref=v1.0.0"

  subscription          = var.subscription
  naming                = var.naming
  connectivity_type     = var.connectivity_type
  platform_shared_state = var.platform_shared_state
  hub_region_mapping    = var.hub_region_mapping
  tags                  = var.tags
  vending               = var.vending
  management            = var.management
  compute               = var.compute
}
```

## What It Orchestrates

- [AVM Subscription Vending](https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest) (resource groups, VNets, NSGs, route tables, UMIs, role assignments)
- [scc-workload-management](https://github.com/TysonTech-net/terraform-azurerm-scc-workload-management) (Recovery Services Vault, Key Vault, Update Manager)
- [scc-workload-vm](https://github.com/TysonTech-net/terraform-azurerm-scc-workload-vm) (Virtual Machines with AVM, backup, maintenance, ASR/BCDR)

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.12 |
| azurerm | ~> 4.0 |
| azapi | ~> 2.0 |
