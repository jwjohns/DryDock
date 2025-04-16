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

# --- Resource Group --- #
resource "azurerm_resource_group" "rg" {
  name     = "drydock-azure-rg" # Consider parameterizing name via cargo
  location = var.location
}

# --- Networking --- #
resource "azurerm_virtual_network" "vnet" {
  name                = "drydock-azure-vnet" # Consider parameterizing name
  address_space       = ["10.11.0.0/16"]      # Example CIDR - Choose appropriate range
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "drydock-azure-subnet" # Consider parameterizing name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.11.0.0/24"]      # Example CIDR - Must be within VNet range

  # For AKS integration, potentially delegate subnet to ContainerInstance or specific services
  # delegation {
  #   name = "aks-delegation"
  #   service_delegation {
  #     name = "Microsoft.ContainerInstance/containerGroups"
  #     actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
  #   }
  # }
}

# --- AKS Cluster --- #
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "drydock-azure-cluster" # Consider parameterizing name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "drydockaks"          # Choose a unique DNS prefix

  default_node_pool {
    name       = "default"
    node_count = 1 # Adjust as needed
    vm_size    = "Standard_DS2_v2" # Choose appropriate VM size
    vnet_subnet_id = azurerm_subnet.subnet.id # Attach to our subnet
  }

  # Use System Assigned Identity for simplicity, or User Assigned for more control
  identity {
    type = "SystemAssigned"
  }

  # Enable Workload Identity (Federated Identity Credentials setup needed on App Registration)
  # oidc_issuer_enabled = true
  # workload_identity_enabled = true # Requires specific API versions

  # Other common settings:
  # network_profile {
  #   network_plugin = "azure"
  #   network_policy = "azure" # or "calico"
  #   service_cidr = "10.12.0.0/16"
  #   dns_service_ip = "10.12.0.10"
  #   docker_bridge_cidr = "172.17.0.1/16"
  # }
  # addon_profile {
  #   oms_agent {
  #     enabled = true
  #     log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id
  #   }
  #   azure_policy {
  #     enabled = true
  #   }
  # }

  # IMPORTANT: Further RBAC configuration and potential User Assigned Identity setup needed
  # Requires assigning roles like 'AcrPull' to the AKS identity to pull from ACR, etc.
}

# --- IAM/RBAC for WIF (Example - Requires More Detail) --- #
# The Service Principal associated with your GitHub Actions Azure WIF credential
# needs appropriate roles assigned to manage the resources above (e.g., Contributor on the RG).
# This is typically done outside this Terraform config or via a separate higher-privilege run.

# Also, for Azure WIF with AKS Workloads, you need to:
# 1. Enable OIDC issuer on the AKS cluster (see above `oidc_issuer_enabled`).
# 2. Create Federated Identity Credentials on the Azure AD App Registration(s) used by your K8s workloads,
#    linking them to the Kubernetes Service Account (issuer URL, namespace, SA name).
# 3. Grant the Azure AD App Registration(s) the necessary Azure roles (e.g., Key Vault Secrets User).

# --- Outputs (Optional) --- #
output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_kubeconfig_raw" {
  description = "Raw Kubeconfig for the AKS cluster (admin credentials)"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "resource_group_name" {
  description = "Resource Group name"
  value       = azurerm_resource_group.rg.name
}

# Example: Define shared Azure infrastructure here, like Resource Groups, VNETs, AKS clusters etc.
# This is the 'static' part of your Azure infrastructure.

# module "aks_cluster" {
#   source = "../modules/aks_cluster" # Assuming a module exists
#   ...
# } 