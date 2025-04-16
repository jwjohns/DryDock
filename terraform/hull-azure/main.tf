terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0" # Or a more specific version
    }
  }

  # Backend configuration for Azure - uncomment and configure
  # backend "azurerm" {
  #   resource_group_name  = "your-tfstate-rg"
  #   storage_account_name = "yourtfstatestorageaccount"
  #   container_name       = "tfstate"
  #   key                  = "drydock/hull-azure/terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}

  # Authentication details for Azure:
  # When running in GitHub Actions with Azure WIF (azure/login action),
  # authentication is handled automatically via OIDC.
  # For local execution (like render.sh), you might need to set environment variables
  # (ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID) or use `az login`.
  # subscription_id = var.subscription_id
  # tenant_id       = var.tenant_id
}

# --- Variables --- #
variable "subscription_id" {
  description = "The Azure Subscription ID."
  type        = string
}

variable "tenant_id" {
  description = "The Azure Tenant ID."
  type        = string
}

variable "location" {
  description = "The primary Azure region for resources."
  type        = string
  # Example: default = "East US"
}

# --- Resources defined in the Azure Hull --- #

# Example: Define shared Azure infrastructure here, like Resource Groups, VNETs, AKS clusters etc.
# This is the 'static' part of your Azure infrastructure.

# module "aks_cluster" {
#   source = "../modules/aks_cluster" # Assuming a module exists
#   ...
# } 