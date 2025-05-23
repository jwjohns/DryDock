# Local Development and Testing Guide for Drydock

This document provides instructions and tips for setting up your local environment to work with Drydock, test configurations, and simulate parts of the CI/CD workflow.

## Table of Contents
* [Introduction](#introduction)
* [1. Simulating Cloud Authentication Locally (Mimicking WIF)](#1-simulating-cloud-authentication-locally-mimicking-wif)
    * [GCP Local Setup (`gcloud`)](#gcp-local-setup-gcloud)
    * [Azure Local Setup (`az` CLI)](#azure-local-setup-az-cli)
    * [Important Considerations](#important-considerations)
* [2. Validating Cargo Files](#2-validating-cargo-files)
    * [Using `validate_cargo.sh`](#using-validate_cargosh)
* [3. Local Rendering and Dry-Runs with `render.sh`](#3-local-rendering-and-dry-runs-with-rendersh)
    * [Basic Usage](#basic-usage)
    * [Validating Cargo Files during Render](#validating-cargo-files-during-render)
    * [Using Local Secret Files for Rendering](#using-local-secret-files-for-rendering)
* [4. General Tips for Local Testing](#4-general-tips-for-local-testing)

## Introduction

While Drydock's full power is realized in its GitHub Actions workflow using Workload Identity Federation (WIF), effective local development is crucial for iterating on configurations and understanding behavior. This guide helps you set up your local environment to best approximate the workflow's operations.

## 1. Simulating Cloud Authentication Locally (Mimicking WIF)

The Drydock GitHub Actions workflow uses WIF to authenticate to GCP and Azure without long-lived secrets. Locally, you cannot directly perform WIF in the same way. Instead, you will use your user credentials via the cloud provider's CLI to achieve similar access for development purposes.

### GCP Local Setup (`gcloud`)

1.  **Install Google Cloud SDK:** Ensure you have `gcloud` CLI installed and configured.
2.  **User Authentication:**
    *   Authenticate as a user: `gcloud auth login`
    *   Set up Application Default Credentials (ADC): `gcloud auth application-default login`
    This allows local tools like Terraform and `gsutil` (if used directly) to authenticate as you.
3.  **Permissions:**
    Your authenticated GCP user needs IAM permissions in the target project similar to those granted to Drydock's WIF Service Account (e.g., `drydock-workflow-sa`). This typically includes:
    *   Read access to GCS cargo buckets (e.g., `roles/storage.objectViewer`). If you plan to upload/modify cargo files locally for testing, you might need `roles/storage.objectAdmin`.
    *   Read access to GCP Secret Manager secrets (e.g., `roles/secretmanager.secretAccessor`).
    *   Permissions for GKE if running `kubectl` locally (e.g., `roles/container.clusterViewer` and appropriate Kubernetes RBAC within the cluster).
    *   It's advisable to use the principle of least privilege. Consult your GCP project admins about appropriate developer roles or groups.
4.  **Terraform/Helm Usage:**
    The Terraform GCP provider and Helm (if configured with a GCS backend or interacting with GCP services) will typically pick up these Application Default Credentials automatically.

### Azure Local Setup (`az` CLI)

1.  **Install Azure CLI:** Ensure you have `az` CLI installed.
2.  **User Authentication:**
    *   Log in as a user: `az login`
    This allows local tools like Terraform and `az cli` itself to authenticate as you.
3.  **Permissions:**
    Your authenticated Azure user needs role assignments in the target subscription similar to those granted to Drydock's WIF Service Principal. This includes:
    *   Read access to Azure Blob Storage cargo containers (e.g., "Storage Blob Data Reader"). If modifying cargo locally, you might need "Storage Blob Data Contributor."
    *   Read access to Azure Key Vault secrets (e.g., "Key Vault Secrets User").
    *   Permissions for AKS if running `kubectl` locally (e.g., "Azure Kubernetes Service Cluster User Role").
    *   Consult your Azure administrators about appropriate Azure AD groups or custom roles.
4.  **Terraform/Helm Usage:**
    The Terraform AzureRM provider and Helm will typically use the credentials from your active `az login` session.

### Important Considerations

*   **User Credentials vs. WIF Identity:** Remember that this local setup uses *your user credentials*. Audit logs in GCP/Azure will reflect your identity, not the WIF Service Account/Principal used by the GitHub Actions workflow.
*   **Development Convenience:** This local authentication method is for development and testing convenience. It does not replace the security model of WIF used in the CI/CD pipeline.
*   **Least Privilege:** Avoid using highly privileged user accounts for routine local development. Use accounts or groups with the minimum necessary permissions.

## 2. Validating Cargo Files

Before uploading your cargo files (`.tfvars` for Terraform, `override.yaml` for Helm) to cloud storage, or when testing locally with `render.sh`, you can validate their syntax and basic structure using the `validate_cargo.sh` script.

### Using `validate_cargo.sh`

The script is located at `scripts/local_dev/validate_cargo.sh`.

**Syntax:**
```bash
./scripts/local_dev/validate_cargo.sh <cloud_target> <env_name> <file_type> <file_path>
```
*   `<cloud_target>`: `gcp` or `azure`.
*   `<env_name>`: Environment name (e.g., `dev`, `prod`). (Currently for context, may be used for future validation rules).
*   `<file_type>`:
    *   `tfvars`: For Terraform HCL variable files.
    *   `helm`: For Helm YAML override files.
*   `<file_path>`: Path to the local cargo file you want to validate.

**Examples:**
```bash
# Validate a GCP Terraform cargo file
./scripts/local_dev/validate_cargo.sh gcp dev tfvars ./terraform/cargo/dev.tfvars.example

# Validate an Azure Helm override file
./scripts/local_dev/validate_cargo.sh azure dev helm ./helm/cargo/azure-dev-override.yaml.example
```

**Validation Performed:**
*   **For `tfvars` files:** Checks HCL syntax and formatting using `terraform fmt -check -diff`. Requires `terraform` CLI to be installed.
*   **For `helm` (YAML) files:**
    *   If `yamllint` is installed, it performs a strict lint using `yamllint --strict`.
    *   If `yamllint` is not found but `python3` is, it performs a basic YAML structure check by attempting to parse the file.
    *   If neither is found, a warning is issued, and advanced YAML validation is skipped.

The script will output success or failure messages and relevant error details from the underlying tools.

## 3. Local Rendering and Dry-Runs with `render.sh`

The `scripts/render.sh` script allows you to perform a local dry-run of Terraform and Helm operations, similar to what the CI/CD workflow does. It generates a Terraform plan and renders Helm templates.

Refer to the comments within `scripts/render.sh` for basic usage. The enhanced version includes:

### Basic Usage
Select the cloud target (defaults to `gcp` if no argument is provided):
```bash
./scripts/render.sh gcp
# or
./scripts/render.sh azure
```
This will use the default `.example` cargo files for the `dev` environment. You can override the cargo files used by setting `TF_CARGO_FILE` and `HELM_CARGO_FILE` environment variables before running the script.

### Validating Cargo Files during Render
You can instruct `render.sh` to validate the cargo files it uses by passing the `-v` or `--validate-cargo` flag:
```bash
./scripts/render.sh -v gcp
# or
./scripts/render.sh --validate-cargo azure
```
If validation fails for either the Terraform or Helm cargo file, `render.sh` will exit before attempting to render.

### Using Local Secret Files for Rendering
The Drydock workflow fetches secrets (e.g., API keys, database passwords) from cloud vaults and makes them available to Terraform and Helm in files named `terraform/cargo/secrets.auto.tfvars` and `helm/cargo/secrets.yaml` respectively.

To simulate this locally with `render.sh`:
1.  Create local versions of these files with the necessary secret values:
    *   `terraform/cargo/secrets.auto.tfvars` (in HCL format)
    *   `helm/cargo/secrets.yaml` (in YAML format)
    *(Ensure these actual secret files are listed in your global `.gitignore` if you create them within your project directory, though they are already in the project's `.gitignore`)*

2.  Run `render.sh` as usual. If these local secret files exist at the expected paths, `render.sh` will automatically include them in the `terraform plan` and `helm template` commands:
    *   `terraform plan ... -var-file=../../terraform/cargo/secrets.auto.tfvars ...`
    *   `helm template ... -f ./helm/cargo/secrets.yaml ...`

This allows you to test how your configurations would behave with secrets injected, without needing to pull them from a live vault during local rendering.

## 4. General Tips for Local Testing

*   **Iterate Quickly:** Use `render.sh` frequently with your local cargo file changes before uploading them.
*   **Terraform Console:** For testing Terraform interpolations or variable values, use `terraform console` within the appropriate hull directory (e.g., `terraform/hull-gcp`).
*   **Helm Debugging:** Use `helm template --debug` or `helm install --dry-run --debug` to get more insight into Helm chart rendering.
*   **Small Changes:** Make small, incremental changes to your cargo files or infrastructure code and test them. This makes troubleshooting easier.
*   **Version Control:** Keep your local cargo file examples (or actual test versions, if not sensitive) under version control in a separate branch or using a safe naming convention if you are actively developing them. **Never commit actual secrets.**

By using these local development techniques, you can build and test your Drydock configurations more efficiently and with greater confidence before pushing them to trigger the CI/CD workflow.
```
