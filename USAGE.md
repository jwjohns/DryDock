# Drydock Workflow Usage and Configuration

This document provides detailed instructions on how to configure and use the Drydock deployment workflow.

## Workflow Overview

The primary deployment workflow is defined in `.github/workflows/deploy.yaml`. It is designed to deploy infrastructure and applications to GCP and Azure using Terraform and Helm, leveraging Workload Identity Federation for secure authentication.

The workflow performs the following key operations:
1. Authenticates to the target cloud (GCP or Azure) using WIF.
2. Fetches environment-specific configuration ("cargo") from cloud storage.
3. Fetches secrets from GCP Secret Manager or Azure Key Vault, making them available as temporary files for Terraform and Helm.
4. Lints and validates Terraform and Helm configurations.
5. Deploys Terraform infrastructure.
6. Deploys Helm charts to Kubernetes.

For tips on how to test and iterate on your configurations locally before running the workflow, please see the **[Local Development and Testing Guide](LOCAL_DEVELOPMENT.md)**.

## Configuration

**Note:** Before proceeding with the configuration below, ensure you have set up the necessary cloud provider resources using our **[Drydock Bootstrapping Guide](BOOTSTRAPPING.md)**. That guide will help you create the required infrastructure and will provide some of the GitHub Secret values mentioned here.

To use this workflow, you need to configure several GitHub Secrets in your repository settings and set up cloud storage for your cargo files.

### 1. GitHub Secrets

The following GitHub Secrets must be created in your repository (`Settings -> Secrets and variables -> Actions -> New repository secret`):

**General Secrets:**
*   `GCP_WORKLOAD_IDENTITY_PROVIDER`: The full path of your GCP Workload Identity Provider (e.g., `projects/123456789/locations/global/workloadIdentityPools/my-pool/providers/my-provider`).
*   `GCP_SERVICE_ACCOUNT_EMAIL`: The email address of the GCP Service Account to impersonate via WIF (e.g., `your-sa@your-gcp-project-id.iam.gserviceaccount.com`).
*   `AZURE_CLIENT_ID`: The Client ID of the Azure AD Application Registration enabled for WIF.
*   `AZURE_TENANT_ID`: The Azure AD Tenant ID.
*   `AZURE_SUBSCRIPTION_ID`: Your Azure Subscription ID.

**Cargo Storage Secrets:**
*   `GCP_CARGO_BUCKET`: The name of the GCS bucket where GCP cargo files are stored (e.g., `my-gcp-cargo-bucket`).
*   `AZURE_CARGO_STORAGE_ACCOUNT`: The name of the Azure Storage Account where Azure cargo files are stored (e.g., `myazcargoaccount`).
*   `AZURE_CARGO_CONTAINER`: The name of the Azure Blob Container within the storage account for Azure cargo files (e.g., `cargo`).

**Kubernetes Cluster Secrets:**
*   `GCP_PROJECT_ID`: The GCP Project ID where the GKE cluster is located.
*   `GKE_CLUSTER_NAME`: The name of your GKE cluster.
*   `GCP_REGION`: The GCP region where your GKE cluster is located (e.g., `us-central1`).
*   `AZURE_AKS_RESOURCE_GROUP`: The name of the Azure Resource Group containing your AKS cluster.
*   `AZURE_AKS_CLUSTER_NAME`: The name of your AKS cluster.

**Cloud Secret Vault Secrets:**
*   `AZURE_KEY_VAULT_NAME`: The name of your Azure Key Vault instance from which secrets will be pulled (e.g., `myproject-kv`). (Required if using Azure and want to pull secrets from Key Vault).

### 2. Cargo File Setup

"Cargo" files provide environment-specific configurations for your Terraform and Helm deployments. These files are *not* stored in the Git repository but are fetched by the workflow from your cloud storage provider during deployment.

**Naming Convention and Structure:**

You need to create and upload your cargo files to the configured cloud storage locations. The workflow expects the following naming conventions:

*   **GCP Terraform Cargo:**
    *   Location: GCS Bucket (`${{ secrets.GCP_CARGO_BUCKET }}`)
    *   Path in bucket: `terraform/<environment_name>.tfvars`
    *   Example: For a `dev` environment, upload `dev.tfvars` to `gs://<GCP_CARGO_BUCKET_NAME>/terraform/dev.tfvars`.
*   **GCP Helm Cargo (Overrides):**
    *   Location: GCS Bucket (`${{ secrets.GCP_CARGO_BUCKET }}`)
    *   Path in bucket: `helm/<environment_name>.override.yaml`
    *   Example: For a `dev` environment, upload `dev.override.yaml` to `gs://<GCP_CARGO_BUCKET_NAME>/helm/dev.override.yaml`.
*   **Azure Terraform Cargo:**
    *   Location: Azure Blob Storage (`${{ secrets.AZURE_CARGO_STORAGE_ACCOUNT }}`, container `${{ secrets.AZURE_CARGO_CONTAINER }}`)
    *   Blob name: `terraform/azure-<environment_name>.tfvars`
    *   Example: For a `dev` environment, upload `azure-dev.tfvars` as blob `terraform/azure-dev.tfvars` in your container.
*   **Azure Helm Cargo (Overrides):**
    *   Location: Azure Blob Storage (`${{ secrets.AZURE_CARGO_STORAGE_ACCOUNT }}`, container `${{ secrets.AZURE_CARGO_CONTAINER }}`)
    *   Blob name: `helm/azure-<environment_name>.override.yaml`
    *   Example: For a `dev` environment, upload `azure-dev.override.yaml` as blob `helm/azure-dev.override.yaml` in your container.

The `<environment_name>` corresponds to the `environment` input provided when dispatching the workflow (e.g., `dev`, `staging`, `prod`).

**Example Files:**
The repository contains example cargo files in `terraform/cargo/` and `helm/cargo/` (e.g., `dev.tfvars.example`, `azure-dev-override.yaml.example`). You can use these as templates for creating your actual cargo files in cloud storage. Remember to remove the `.example` suffix for the files stored in the cloud.

### 3. Secrets Management in Cloud Vaults

The workflow can pull secrets directly from GCP Secret Manager or Azure Key Vault. These secrets are then made available to Terraform as a `.tfvars` file and to Helm as a YAML values file.

**Configuration in Your Cloud Vault:**

You need to create secrets in your cloud provider's vault with specific names and content formats for the workflow to retrieve them:

*   **Terraform Secrets File (`terraform/cargo/secrets.auto.tfvars`):**
    *   **GCP Secret Manager Secret ID:** `tf-secrets.auto.tfvars`
    *   **Azure Key Vault Secret Name:** `tf-secrets-auto-tfvars` (Note: periods are replaced with hyphens for Azure Key Vault compatibility).
    *   **Content Format (HCL):** The content of this secret should be in HCL format, suitable for a `.tfvars` file. Example:
        ```hcl
        api_key = "abcdef123456"
        db_password = "supersecretpassword"
        ```

*   **Helm Secrets File (`helm/cargo/secrets.yaml`):**
    *   **GCP Secret Manager Secret ID:** `helm-secrets.yaml`
    *   **Azure Key Vault Secret Name:** `helm-secrets-yaml`
    *   **Content Format (YAML):** The content of this secret should be in YAML format, suitable for a Helm values file. Example:
        ```yaml
        replicaApiKey: "xyz7890123"
        ingress:
          tlsSecretName: "my-tls-secret-from-vault"
        ```

**Workflow Behavior:**

*   During the "Pull Secrets" step, the workflow attempts to fetch these secrets based on the `CLOUD_TARGET`.
*   If a secret is found and pulled:
    *   Its content is saved to `terraform/cargo/secrets.auto.tfvars` or `helm/cargo/secrets.yaml` in the runner.
    *   These files are then automatically used by the `terraform validate`, `terraform plan`, `helm lint`, and `helm upgrade` commands.
*   If a secret is not found in the vault (or if there's a permissions issue), a warning is logged, the corresponding local file (`secrets.auto.tfvars` or `secrets.yaml`) will be empty, and the workflow continues. Terraform or Helm might fail later if they critically depend on a missing secret.
*   These temporary secret files are always cleaned up at the end of the workflow run.
*   The filenames `terraform/cargo/secrets.auto.tfvars` and `helm/cargo/secrets.yaml` are included in `.gitignore`.

## Running the Workflow

1.  Ensure all necessary GitHub Secrets (listed above) are configured.
2.  Ensure your cargo files are correctly named and uploaded to the specified GCS bucket or Azure Blob container.
3.  Trigger the workflow via a push to the configured branch (e.g., `main`) or by manual dispatch (`Actions -> Drydock Multi-Cloud Deploy -> Run workflow`).
    *   When dispatching manually, specify the `cloud` (`gcp` or `azure`) and `environment` (e.g., `dev`).
