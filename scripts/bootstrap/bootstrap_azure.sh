#!/bin/bash

# Purpose: Bootstraps necessary Azure resources for the Drydock workflow.
#
# Prerequisites:
# 1. Azure CLI (`az`) installed and authenticated: `az login`.
# 2. Sufficient IAM permissions for the authenticated user. Typically, this means:
#    - Owner or Contributor role on the Subscription.
#    - OR specific roles:
#      - To create App Registrations and Service Principals: Application Administrator or Cloud Application Administrator.
#      - To create Resource Groups: Contributor at subscription level or Resource Policy Contributor.
#      - To create Storage Accounts, Key Vaults: Contributor on the Resource Group or specific resource creation roles.
#      - To assign roles (RBAC): User Access Administrator or Owner on the relevant scopes.
#      - For Key Vault RBAC: Key Vault Contributor or User Access Administrator on the Key Vault.
#      - For Storage Blob Data operations (if creating container with --auth-mode login): Storage Blob Data Contributor/Owner.
#
# Usage:
#   Set environment variables OR pass as arguments:
#   export AZURE_SUBSCRIPTION_ID="your-subscription-id"
#   export GITHUB_ORG_REPO="your-org/your-repo"
#   export RESOURCE_GROUP_NAME="your-rg-name"
#   export AZURE_REGION="eastus" # e.g., eastus, westus2
#
#   Run the script:
#   ./scripts/bootstrap/bootstrap_azure.sh
#
#   Alternatively, pass as arguments (SUBSCRIPTION_ID GITHUB_ORG_REPO RESOURCE_GROUP_NAME AZURE_REGION [APP_REG_NAME] ...):
#   ./scripts/bootstrap/bootstrap_azure.sh "sub-id" "org/repo" "rg-name" "eastus"
#
# Optional environment variables (or script arguments in order after required ones):
#   APP_REG_NAME (default: drydock-github-wif-app)
#   STORAGE_ACCOUNT_NAME (default: drydockcargo<random_hex>)
#   BLOB_CONTAINER_NAME (default: drydock-cargo)
#   KEY_VAULT_NAME (default: drydock-kv-<random_hex>)
#   FIC_SUBJECT_IDENTIFIER (default: repo:${GITHUB_ORG_REPO}:*)
#   AKS_CLUSTER_NAME (optional, if provided, role assignment for AKS will be attempted)
#   AKS_RESOURCE_GROUP_NAME (optional, required if AKS_CLUSTER_NAME is provided)

set -euo pipefail

usage() {
  echo "Usage: $0 [AZURE_SUBSCRIPTION_ID] [GITHUB_ORG_REPO] [RESOURCE_GROUP_NAME] [AZURE_REGION] [APP_REG_NAME] [STORAGE_ACCOUNT_NAME] [BLOB_CONTAINER_NAME] [KEY_VAULT_NAME] [FIC_SUBJECT_IDENTIFIER] [AKS_CLUSTER_NAME] [AKS_RESOURCE_GROUP_NAME]"
  echo ""
  echo "Arguments can also be set as environment variables (see script comments)."
  echo "  -h, --help    Display this help message."
  exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

# --- User Inputs & Defaults ---
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-${1:-}}"
GITHUB_ORG_REPO="${GITHUB_ORG_REPO:-${2:-}}"
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-${3:-}}"
AZURE_REGION="${AZURE_REGION:-${4:-}}"

APP_REG_NAME="${APP_REG_NAME:-${5:-drydock-github-wif-app}}"
RAND_HEX_4=$(openssl rand -hex 4)
DEFAULT_STORAGE_ACCOUNT_NAME="drydockcargo${RAND_HEX_4}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-${6:-${DEFAULT_STORAGE_ACCOUNT_NAME}}}"
BLOB_CONTAINER_NAME="${BLOB_CONTAINER_NAME:-${7:-drydock-cargo}}"
DEFAULT_KEY_VAULT_NAME="drydock-kv-${RAND_HEX_4}" # Ensure uniqueness if re-running for same project
KEY_VAULT_NAME="${KEY_VAULT_NAME:-${8:-${DEFAULT_KEY_VAULT_NAME}}}"
DEFAULT_FIC_SUBJECT="repo:${GITHUB_ORG_REPO}:*"
FIC_SUBJECT_IDENTIFIER="${FIC_SUBJECT_IDENTIFIER:-${9:-${DEFAULT_FIC_SUBJECT}}}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-${10:-}}"
AKS_RESOURCE_GROUP_NAME="${AKS_RESOURCE_GROUP_NAME:-${11:-}}"


# Validate required inputs
if [ -z "${AZURE_SUBSCRIPTION_ID}" ]; then
  echo "Error: AZURE_SUBSCRIPTION_ID is not set."
  usage
fi
if [ -z "${GITHUB_ORG_REPO}" ]; then
  echo "Error: GITHUB_ORG_REPO is not set (format: ORG/REPO_NAME)."
  usage
fi
if ! [[ "${GITHUB_ORG_REPO}" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: GITHUB_ORG_REPO format is invalid. Expected 'ORG/REPO_NAME'."
    exit 1
fi
if [ -z "${RESOURCE_GROUP_NAME}" ]; then
  echo "Error: RESOURCE_GROUP_NAME is not set."
  usage
fi
if [ -z "${AZURE_REGION}" ]; then
  echo "Error: AZURE_REGION is not set (e.g., eastus)."
  usage
fi
if [ -n "${AKS_CLUSTER_NAME}" ] && [ -z "${AKS_RESOURCE_GROUP_NAME}" ]; then
    echo "Error: AKS_RESOURCE_GROUP_NAME must be provided if AKS_CLUSTER_NAME is set."
    usage
fi
if [ -z "${AKS_CLUSTER_NAME}" ] && [ -n "${AKS_RESOURCE_GROUP_NAME}" ]; then
    echo "Warning: AKS_RESOURCE_GROUP_NAME is set, but AKS_CLUSTER_NAME is not. No AKS role assignment will be attempted."
fi


echo "--- Configuration ---"
echo "Azure Subscription ID:          ${AZURE_SUBSCRIPTION_ID}"
echo "GitHub Org/Repo:                ${GITHUB_ORG_REPO}"
echo "Resource Group Name:            ${RESOURCE_GROUP_NAME}"
echo "Azure Region:                   ${AZURE_REGION}"
echo "App Registration Name:          ${APP_REG_NAME}"
echo "Storage Account Name:           ${STORAGE_ACCOUNT_NAME}"
echo "Blob Container Name:            ${BLOB_CONTAINER_NAME}"
echo "Key Vault Name:                 ${KEY_VAULT_NAME}"
echo "FIC Subject Identifier:         ${FIC_SUBJECT_IDENTIFIER}"
if [ -n "${AKS_CLUSTER_NAME}" ]; then
echo "AKS Cluster Name:               ${AKS_CLUSTER_NAME}"
echo "AKS Resource Group Name:        ${AKS_RESOURCE_GROUP_NAME}"
fi
echo "---------------------"

read -p "Proceed with creating/configuring these resources? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborted by user."
  exit 0
fi

echo "--- Setting Azure Subscription ---"
az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
echo "Using subscription: $(az account show --query name -o tsv)"

echo "--- Creating Resource Group (if not exists) ---"
if az group show --name "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
  echo "Resource Group '${RESOURCE_GROUP_NAME}' already exists."
else
  az group create --name "${RESOURCE_GROUP_NAME}" --location "${AZURE_REGION}"
  echo "Resource Group '${RESOURCE_GROUP_NAME}' created."
fi

echo "--- Creating AAD Application Registration (if not exists) ---"
APP_CLIENT_ID=$(az ad app list --display-name "${APP_REG_NAME}" --query "[?displayName=='${APP_REG_NAME}'].appId" -o tsv)
if [ -n "${APP_CLIENT_ID}" ]; then
  echo "AAD App Registration '${APP_REG_NAME}' with Client ID '${APP_CLIENT_ID}' already exists. Using existing."
else
  APP_CLIENT_ID=$(az ad app create --display-name "${APP_REG_NAME}" --query appId -o tsv)
  echo "AAD App Registration '${APP_REG_NAME}' created with Client ID '${APP_CLIENT_ID}'."
fi

APP_OBJECT_ID=$(az ad app show --id "${APP_CLIENT_ID}" --query id -o tsv)
echo "AAD App Object ID: ${APP_OBJECT_ID}"

echo "--- Creating Federated Identity Credential ---"
FIC_NAME="github-fic-$(openssl rand -hex 3)"
FIC_JSON=$(cat <<EOF
{
  "name": "${FIC_NAME}",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "${FIC_SUBJECT_IDENTIFIER}",
  "description": "GitHub Actions WIF for ${GITHUB_ORG_REPO}",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
)

# Check if a FIC with the same subject already exists (az ad app federated-credential list does not support filtering by subject directly)
# This is a simple check, a more robust one would iterate and compare subjects.
EXISTING_FIC=$(az ad app federated-credential list --id "${APP_OBJECT_ID}" --query "[?contains(name, 'github-fic-')].name" -o tsv) # Basic check
if [[ "${EXISTING_FIC}" == *"${FIC_NAME_PREFIX_CHECK}"* && -n "${EXISTING_FIC}" ]]; then # Crude check
    echo "A federated credential for GitHub Actions likely already exists for App ${APP_CLIENT_ID}. Skipping creation."
    echo "If you need to update the subject or create a new one, please do so manually in the Azure portal."
else
    if az ad app federated-credential create --id "${APP_OBJECT_ID}" --parameters "${FIC_JSON}"; then
        echo "Federated Identity Credential '${FIC_NAME}' created for App ${APP_CLIENT_ID}."
    else
        echo "Warning: Failed to create Federated Identity Credential. It might already exist with a similar configuration or there was an issue."
        echo "Please check the Azure Portal for App '${APP_REG_NAME}' (${APP_CLIENT_ID})."
    fi
fi


echo "--- Getting Service Principal Object ID ---"
# Ensure SP exists for the App Registration
# If the app was just created, the SP might take a moment to provision.
# Using 'az ad sp create' is idempotent if the SP already exists for the app.
az ad sp create --id "${APP_CLIENT_ID}" > /dev/null 2>&1 # Ensure SP exists
SP_OBJECT_ID=$(az ad sp show --id "${APP_CLIENT_ID}" --query id -o tsv)
if [ -z "${SP_OBJECT_ID}" ]; then
    echo "Error: Could not find Service Principal Object ID for App Client ID ${APP_CLIENT_ID}."
    exit 1
fi
echo "Service Principal Object ID: ${SP_OBJECT_ID}"

echo "--- Creating Storage Account (if not exists) ---"
if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
  echo "Storage Account '${STORAGE_ACCOUNT_NAME}' already exists."
else
  az storage account create --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --location "${AZURE_REGION}" --sku Standard_LRS --kind StorageV2
  echo "Storage Account '${STORAGE_ACCOUNT_NAME}' created."
fi

echo "--- Creating Blob Container (if not exists) ---"
# This command will fail if the container exists but the user does not have permissions to list/create containers.
# Using --fail-on-exist to make it idempotent in behavior.
if az storage container create --name "${BLOB_CONTAINER_NAME}" --account-name "${STORAGE_ACCOUNT_NAME}" --auth-mode login --public-access off --fail-on-exist > /dev/null 2>&1; then
  echo "Blob Container '${BLOB_CONTAINER_NAME}' created in Storage Account '${STORAGE_ACCOUNT_NAME}'."
else
  RET_CODE=$?
  if [ $RET_CODE -eq 3 ]; then # Exit code 3 for "The specified container already exists."
    echo "Blob Container '${BLOB_CONTAINER_NAME}' already exists in Storage Account '${STORAGE_ACCOUNT_NAME}'."
  else
    echo "Failed to create Blob Container '${BLOB_CONTAINER_NAME}'. Return code: $RET_CODE. Ensure you have 'Storage Blob Data Contributor' or similar on the SA or run 'az login' with such user."
    # exit 1 # Decide if this is a fatal error
  fi
fi


echo "--- Creating Key Vault (if not exists) ---"
if az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
  echo "Key Vault '${KEY_VAULT_NAME}' already exists."
else
  az keyvault create --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --location "${AZURE_REGION}" --enable-rbac-authorization true
  echo "Key Vault '${KEY_VAULT_NAME}' created with RBAC authorization enabled."
fi
KEY_VAULT_URI=$(az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query properties.vaultUri -o tsv)


echo "--- Waiting for AAD Propagation for Role Assignments (30 seconds) ---"
sleep 30

echo "--- Assigning Roles to Service Principal '${SP_OBJECT_ID}' ---"
STORAGE_ACCOUNT_SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
az role assignment create --assignee-object-id "${SP_OBJECT_ID}" --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope "${STORAGE_ACCOUNT_SCOPE}" --only-show-errors
echo "Role 'Storage Blob Data Contributor' assigned to SP for Storage Account '${STORAGE_ACCOUNT_NAME}'."

KEY_VAULT_SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
az role assignment create --assignee-object-id "${SP_OBJECT_ID}" --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope "${KEY_VAULT_SCOPE}" --only-show-errors
echo "Role 'Key Vault Secrets User' assigned to SP for Key Vault '${KEY_VAULT_NAME}'."

if [ -n "${AKS_CLUSTER_NAME}" ] && [ -n "${AKS_RESOURCE_GROUP_NAME}" ]; then
  echo "--- Assigning AKS Role (if specified) ---"
  AKS_SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AKS_RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${AKS_CLUSTER_NAME}"
  if az aks show --name "${AKS_CLUSTER_NAME}" --resource-group "${AKS_RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
    az role assignment create --assignee-object-id "${SP_OBJECT_ID}" --assignee-principal-type ServicePrincipal --role "Azure Kubernetes Service Cluster User Role" --scope "${AKS_SCOPE}" --only-show-errors
    echo "Role 'Azure Kubernetes Service Cluster User Role' assigned to SP for AKS Cluster '${AKS_CLUSTER_NAME}'."
  else
    echo "Warning: AKS Cluster '${AKS_CLUSTER_NAME}' in RG '${AKS_RESOURCE_GROUP_NAME}' not found. Skipping role assignment."
  fi
else
  echo "AKS Cluster Name not specified. Skipping AKS role assignment."
fi

AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "--- Bootstrap Complete! ---"
echo ""
echo "--- GitHub Secret Values ---"
echo "Copy these values into your GitHub repository secrets (Settings -> Secrets and variables -> Actions):"
echo ""
echo "AZURE_CLIENT_ID:               ${APP_CLIENT_ID}"
echo "AZURE_TENANT_ID:               ${AZURE_TENANT_ID}"
echo "AZURE_SUBSCRIPTION_ID:         ${AZURE_SUBSCRIPTION_ID}" # (This is the Subscription ID you provided)
echo "AZURE_CARGO_STORAGE_ACCOUNT:   ${STORAGE_ACCOUNT_NAME}"
echo "AZURE_CARGO_CONTAINER:         ${BLOB_CONTAINER_NAME}"
echo "AZURE_KEY_VAULT_NAME:          ${KEY_VAULT_NAME}"
echo ""
echo "--- Important Next Steps ---"
echo "1. Populate your Azure Blob Storage container ('${BLOB_CONTAINER_NAME}' in '${STORAGE_ACCOUNT_NAME}') with environment-specific .tfvars and .override.yaml files."
echo "   Refer to USAGE.md for naming conventions (e.g., terraform/azure-dev.tfvars, helm/azure-dev.override.yaml)."
echo "2. Populate Azure Key Vault ('${KEY_VAULT_NAME}') with secrets named 'tf-secrets-auto-tfvars' and 'helm-secrets-yaml' if you plan to use this feature."
echo "   Refer to USAGE.md for content format. Note Azure Key Vault secret names cannot contain '.' and use '-' instead."
echo ""
echo "To make this script executable: chmod +x scripts/bootstrap/bootstrap_azure.sh"

exit 0
