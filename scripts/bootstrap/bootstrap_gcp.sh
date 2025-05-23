#!/bin/bash

# Purpose: Bootstraps necessary GCP resources for the Drydock workflow.
#
# Prerequisites:
# 1. gcloud CLI installed and authenticated: `gcloud auth login` and `gcloud config set project <YOUR_PROJECT_ID>`.
# 2. Sufficient IAM permissions for the authenticated user (e.g., Project Owner or specific admin roles for IAM,
#    Service Accounts, GCS, Secret Manager, and Workload Identity Federation).
#
# Usage:
#   Set environment variables OR pass as arguments:
#   export GCP_PROJECT_ID="your-gcp-project-id"
#   export GITHUB_ORG_REPO="your-org/your-repo"
#
#   Run the script:
#   ./scripts/bootstrap/bootstrap_gcp.sh
#
#   Alternatively, pass as arguments (PROJECT_ID GITHUB_ORG_REPO):
#   ./scripts/bootstrap/bootstrap_gcp.sh "your-gcp-project-id" "your-org/your-repo"
#
# Optional environment variables (or script arguments in order after required ones):
#   SERVICE_ACCOUNT_NAME (default: drydock-workflow-sa)
#   WORKLOAD_IDENTITY_POOL_ID (default: drydock-pool)
#   WORKLOAD_IDENTITY_PROVIDER_ID (default: github-provider)
#   GCS_CARGO_BUCKET_NAME (default: drydock-cargo-${GCP_PROJECT_ID_LOWERCASE})
#   GCP_REGION (default: US)

set -euo pipefail

usage() {
  echo "Usage: $0 [GCP_PROJECT_ID] [GITHUB_ORG_REPO] [SERVICE_ACCOUNT_NAME] [WORKLOAD_IDENTITY_POOL_ID] [WORKLOAD_IDENTITY_PROVIDER_ID] [GCS_CARGO_BUCKET_NAME] [GCP_REGION]"
  echo ""
  echo "Arguments can also be set as environment variables (see script comments)."
  echo "  -h, --help    Display this help message."
  exit 0
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

# --- User Inputs & Defaults ---
GCP_PROJECT_ID="${GCP_PROJECT_ID:-${1:-}}"
GITHUB_ORG_REPO="${GITHUB_ORG_REPO:-${2:-}}"

SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-${3:-drydock-workflow-sa}}"
WORKLOAD_IDENTITY_POOL_ID="${WORKLOAD_IDENTITY_POOL_ID:-${4:-drydock-pool}}"
WORKLOAD_IDENTITY_PROVIDER_ID="${WORKLOAD_IDENTITY_PROVIDER_ID:-${5:-github-provider}}"
GCP_PROJECT_ID_LOWERCASE=$(echo "${GCP_PROJECT_ID}" | tr '[:upper:]' '[:lower:]')
DEFAULT_BUCKET_NAME="drydock-cargo-${GCP_PROJECT_ID_LOWERCASE}"
GCS_CARGO_BUCKET_NAME="${GCS_CARGO_BUCKET_NAME:-${6:-${DEFAULT_BUCKET_NAME}}}"
GCP_REGION="${GCP_REGION:-${7:-US}}" # Multi-region for GCS bucket

# Validate required inputs
if [ -z "${GCP_PROJECT_ID}" ]; then
  echo "Error: GCP_PROJECT_ID is not set. Please set it as an environment variable or pass as the first argument."
  usage
fi
if [ -z "${GITHUB_ORG_REPO}" ]; then
  echo "Error: GITHUB_ORG_REPO is not set (format: ORG/REPO_NAME). Please set it as an environment variable or pass as the second argument."
  usage
fi
if ! [[ "${GITHUB_ORG_REPO}" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: GITHUB_ORG_REPO format is invalid. Expected 'ORG/REPO_NAME'."
    exit 1
fi

echo "--- Configuration ---"
echo "GCP Project ID:                 ${GCP_PROJECT_ID}"
echo "GitHub Org/Repo:                ${GITHUB_ORG_REPO}"
echo "Service Account Name:           ${SERVICE_ACCOUNT_NAME}"
echo "Workload Identity Pool ID:      ${WORKLOAD_IDENTITY_POOL_ID}"
echo "Workload Identity Provider ID:  ${WORKLOAD_IDENTITY_PROVIDER_ID}"
echo "GCS Cargo Bucket Name:          ${GCS_CARGO_BUCKET_NAME}"
echo "GCS Bucket Region:              ${GCP_REGION}"
echo "---------------------"

read -p "Proceed with creating these resources? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborted by user."
  exit 0
fi

echo "Fetching Project Number for ${GCP_PROJECT_ID}..."
GCP_PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT_ID}" --format='value(projectNumber)')
if [ -z "${GCP_PROJECT_NUMBER}" ]; then
    echo "Error: Failed to fetch project number for ${GCP_PROJECT_ID}. Please ensure the project exists and you have permissions."
    exit 1
fi
echo "Project Number: ${GCP_PROJECT_NUMBER}"

echo "--- Enabling APIs ---"
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  --project="${GCP_PROJECT_ID}"
echo "APIs enabled."

SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

echo "--- Creating Service Account ---"
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${GCP_PROJECT_ID}" > /dev/null 2>&1; then
  echo "Service Account ${SA_EMAIL} already exists. Skipping creation."
else
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${GCP_PROJECT_ID}" \
    --display-name="Drydock Workflow Service Account"
  echo "Service Account ${SA_EMAIL} created."
fi

echo "--- Creating Workload Identity Pool ---"
if gcloud iam workload-identity-pools describe "${WORKLOAD_IDENTITY_POOL_ID}" --project="${GCP_PROJECT_ID}" --location="global" > /dev/null 2>&1; then
  echo "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} already exists. Skipping creation."
else
  gcloud iam workload-identity-pools create "${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${GCP_PROJECT_ID}" \
    --location="global" \
    --display-name="Drydock WIF Pool"
  echo "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} created."
fi

WIF_PROVIDER_FQN="projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/${WORKLOAD_IDENTITY_PROVIDER_ID}"
ALLOWED_AUDIENCE="https://iam.googleapis.com/${WIF_PROVIDER_FQN}" # Audience can be the provider path itself

echo "--- Creating Workload Identity Provider ---"
if gcloud iam workload-identity-pools providers describe "${WORKLOAD_IDENTITY_PROVIDER_ID}" --project="${GCP_PROJECT_ID}" --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" --location="global" > /dev/null 2>&1; then
  echo "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} already exists. Skipping creation."
else
  gcloud iam workload-identity-pools providers create-oidc "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --project="${GCP_PROJECT_ID}" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --location="global" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --allowed-audiences="${ALLOWED_AUDIENCE}" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --display-name="GitHub Actions Provider for Drydock"
  echo "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} created."
fi

echo "--- Setting IAM Policy for WIF (Service Account Impersonation) ---"
# This command is additive, so running it multiple times for the same member/role is generally fine.
# However, for true idempotency, one might check if the binding already exists, which is more complex.
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${GCP_PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_ORG_REPO}"
echo "IAM policy binding for WIF set on Service Account ${SA_EMAIL}."


echo "--- Creating GCS Bucket for Cargo ---"
BUCKET_URI="gs://${GCS_CARGO_BUCKET_NAME}"
if gsutil ls -b "${BUCKET_URI}" > /dev/null 2>&1; then
  echo "GCS Bucket ${BUCKET_URI} already exists. Skipping creation."
else
  gsutil mb -p "${GCP_PROJECT_ID}" -l "${GCP_REGION}" "${BUCKET_URI}"
  echo "GCS Bucket ${BUCKET_URI} created."
fi

echo "--- Setting Uniform Bucket-Level Access ---"
gsutil uniformbucketlevelaccess set on "${BUCKET_URI}"
echo "Uniform bucket-level access set on ${BUCKET_URI}."

echo "--- Setting IAM Policy for GCS Bucket Access ---"
# gsutil iam ch is idempotent in effect.
gsutil iam ch "serviceAccount:${SA_EMAIL}:objectAdmin" "${BUCKET_URI}"
echo "IAM policy for SA ${SA_EMAIL} to be objectAdmin on ${BUCKET_URI} set."

echo "--- Setting IAM Policy for Secret Manager Access ---"
# This command is additive.
gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"
echo "IAM policy for SA ${SA_EMAIL} to be secretmanager.secretAccessor on project ${GCP_PROJECT_ID} set."

echo "--- Bootstrap Complete! ---"
echo ""
echo "--- GitHub Secret Values ---"
echo "Copy these values into your GitHub repository secrets (Settings -> Secrets and variables -> Actions):"
echo ""
echo "GCP_WORKLOAD_IDENTITY_PROVIDER: ${WIF_PROVIDER_FQN}"
echo "GCP_SERVICE_ACCOUNT_EMAIL:      ${SA_EMAIL}"
echo "GCP_CARGO_BUCKET:               ${GCS_CARGO_BUCKET_NAME}"
echo "GCP_PROJECT_ID:                 ${GCP_PROJECT_ID}" # (This is the Project ID you provided)
echo ""
echo "--- Important Next Steps ---"
echo "1. Populate your GCS cargo bucket ('${GCS_CARGO_BUCKET_NAME}') with environment-specific .tfvars and .override.yaml files."
echo "   Refer to USAGE.md for naming conventions (e.g., terraform/dev.tfvars, helm/dev.override.yaml)."
echo "2. Populate GCP Secret Manager with secrets named 'tf-secrets.auto.tfvars' and 'helm-secrets.yaml' if you plan to use this feature."
echo "   Refer to USAGE.md for content format."
echo "3. Ensure the GitHub repository '${GITHUB_ORG_REPO}' has granted access to this Workload Identity Provider if necessary (org/repo settings)."
echo ""
echo "To make this script executable: chmod +x scripts/bootstrap/bootstrap_gcp.sh"

exit 0
