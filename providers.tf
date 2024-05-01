terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.100.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true
    }

  }
}

data "azurerm_client_config" "client_config" {}
