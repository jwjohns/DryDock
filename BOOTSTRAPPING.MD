# Drydock Bootstrapping Guide

This guide provides instructions on how to use the bootstrapping scripts to set up the necessary cloud provider resources for Drydock. These scripts help automate the creation of Workload Identity Federation configurations, service accounts/principals, storage for cargo files, and secret vaults.

## Prerequisites

Before running either bootstrapping script, ensure you have the following:

*   **Git:** To clone the Drydock repository (or your fork).
*   **GitHub Repository:** You should have a GitHub repository where you intend to use Drydock. You'll need its name in the format `ORGANIZATION_NAME/REPOSITORY_NAME`.
*   **Permissions:** You will need sufficient permissions in your cloud account (GCP Project or Azure Subscription) to create the resources outlined by the scripts. Typically, roles like "Project Owner" in GCP or "Contributor" / "Owner" in Azure are sufficient, or a combination of more specific admin roles (e.g., for IAM, Storage, Key Vault/Secret Manager).

### For GCP Bootstrapping (`bootstrap_gcp.sh`):
*   **Google Cloud SDK (`gcloud`):** Installed and configured.
*   **Authentication:** Authenticated to `gcloud` with an account that has the necessary permissions in your target GCP project (e.g., run `gcloud auth login` and `gcloud auth application-default login`).

### For Azure Bootstrapping (`bootstrap_azure.sh`):
*   **Azure CLI (`az`):** Installed and configured.
*   **Authentication:** Authenticated to `az` with an account that has the necessary permissions in your target Azure subscription (e.g., run `az login`).

## Using the GCP Bootstrapping Script (`scripts/bootstrap/bootstrap_gcp.sh`)

This script automates the setup of:
*   GCP Workload Identity Pool and Provider.
*   A GCP Service Account for GitHub Actions.
*   IAM bindings to allow WIF and grant the Service Account access to GCS (for cargo) and Secret Manager.
*   A GCS bucket for Drydock cargo files.

### Steps:

1.  **Navigate to the script directory:**
    ```bash
    cd scripts/bootstrap
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x bootstrap_gcp.sh
    ```

3.  **Run the script:**
    You'll need to provide your GCP Project ID and your GitHub repository information.

    **Option 1: Using Environment Variables:**
    ```bash
    export GCP_PROJECT_ID="your-gcp-project-id"
    export GITHUB_ORG_REPO="YOUR_ORG/YOUR_REPO"
    # Optional: set other variables like SERVICE_ACCOUNT_NAME, GCS_CARGO_BUCKET_NAME, etc.
    ./bootstrap_gcp.sh
    ```

    **Option 2: Using Script Arguments:**
    ```bash
    ./bootstrap_gcp.sh --project-id "your-gcp-project-id" --github-repo "YOUR_ORG/YOUR_REPO" \
                       [--sa-name "custom-sa-name"] \
                       [--pool-id "custom-pool-id"] \
                       [--provider-id "custom-provider-id"] \
                       [--bucket-name "custom-bucket-name"] \
                       [--region "US-CENTRAL1"] # Optional region for GCS bucket
    ```
    Use `./bootstrap_gcp.sh --help` to see all available options and their defaults.

4.  **Confirm Execution:**
    The script will display the configuration it intends to apply and ask for your confirmation before proceeding.

5.  **Collect GitHub Secret Values:**
    Once the script completes successfully, it will output a list of GitHub Secret names and their corresponding values. These are:
    *   `GCP_WORKLOAD_IDENTITY_PROVIDER`
    *   `GCP_SERVICE_ACCOUNT_EMAIL`
    *   `GCP_CARGO_BUCKET`
    *   `GCP_PROJECT_ID`

6.  **Configure GitHub Secrets:**
    Navigate to your GitHub repository's `Settings -> Secrets and variables -> Actions` and create new repository secrets with the names and values provided by the script.

7.  **Next Steps for GCP:**
    *   Upload your environment-specific cargo files (e.g., `dev.tfvars`, `dev.override.yaml`) to the created GCS cargo bucket under the paths `terraform/<env>.tfvars` and `helm/<env>.override.yaml` respectively.
    *   Store any sensitive values for Terraform or Helm in GCP Secret Manager under the names `tf-secrets.auto.tfvars` and `helm-secrets.yaml` as detailed in `USAGE.md`.

## Using the Azure Bootstrapping Script (`scripts/bootstrap/bootstrap_azure.sh`)

This script automates the setup of:
*   Azure AD Application Registration with a Federated Identity Credential for GitHub Actions.
*   Role assignments for the App's Service Principal to access Azure Blob Storage (for cargo), Azure Key Vault (for secrets), and optionally an existing AKS cluster.
*   An Azure Storage Account and Blob Container for Drydock cargo files.
*   An Azure Key Vault for storing secrets.

### Steps:

1.  **Navigate to the script directory:**
    ```bash
    cd scripts/bootstrap
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x bootstrap_azure.sh
    ```

3.  **Run the script:**
    You'll need to provide your Azure Subscription ID, GitHub repository information, a Resource Group name (the script will create it if it doesn't exist), and an Azure region.

    **Option 1: Using Environment Variables:**
    ```bash
    export AZURE_SUBSCRIPTION_ID="your-subscription-id"
    export GITHUB_ORG_REPO="YOUR_ORG/YOUR_REPO"
    export RESOURCE_GROUP_NAME="my-drydock-resources-rg"
    export AZURE_REGION="eastus"
    # Optional: set other variables like APP_REG_NAME, STORAGE_ACCOUNT_NAME, etc.
    ./bootstrap_azure.sh
    ```

    **Option 2: Using Script Arguments:**
    ```bash
    ./bootstrap_azure.sh --subscription-id "your-subscription-id" \
                       --github-repo "YOUR_ORG/YOUR_REPO" \
                       --resource-group "my-drydock-resources-rg" \
                       --location "eastus" \
                       [--app-name "custom-app-reg-name"] \
                       [--storage-account-name "customstoragename"] \
                       [--container-name "customcontainer"] \
                       [--keyvault-name "customkeyvault"] \
                       [--aks-cluster-name "my-aks-cluster"] \
                       [--aks-resource-group "my-aks-cluster-rg"]
    ```
    Use `./bootstrap_azure.sh --help` to see all available options and their defaults.

4.  **Confirm Execution:**
    The script will display the configuration it intends to apply and ask for your confirmation.

5.  **Collect GitHub Secret Values:**
    Upon successful completion, the script will output:
    *   `AZURE_CLIENT_ID`
    *   `AZURE_TENANT_ID`
    *   `AZURE_SUBSCRIPTION_ID`
    *   `AZURE_CARGO_STORAGE_ACCOUNT`
    *   `AZURE_CARGO_CONTAINER`
    *   `AZURE_KEY_VAULT_NAME`

6.  **Configure GitHub Secrets:**
    In your GitHub repository's `Settings -> Secrets and variables -> Actions`, create new repository secrets with these names and values.

7.  **Next Steps for Azure:**
    *   Upload your environment-specific cargo files (e.g., `azure-dev.tfvars`, `azure-dev.override.yaml`) to the created Azure Blob container under the paths `terraform/azure-<env>.tfvars` and `helm/azure-<env>.override.yaml` respectively.
    *   Store any sensitive values for Terraform or Helm in the created Azure Key Vault under the names `tf-secrets-auto-tfvars` and `helm-secrets-yaml` as detailed in `USAGE.md`. Remember that names in Key Vault use hyphens instead of periods.

## Post-Bootstrapping

After running the appropriate script(s) and configuring GitHub Secrets:
*   Your Drydock workflow should be ready to authenticate to your cloud provider using Workload Identity Federation.
*   Ensure your cargo files and any necessary secrets are populated in the cloud storage and vaults as described in `USAGE.md`.
*   You can now run the Drydock workflow (`.github/workflows/deploy.yaml`).

Refer to `USAGE.md` for detailed information on workflow inputs, cargo file structure, and secret management within Drydock.
Additionally, for guidance on testing your configurations locally and simulating parts of the CI/CD workflow, see our **[Local Development and Testing Guide](LOCAL_DEVELOPMENT.md)**.
```
