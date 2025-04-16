#!/bin/bash
set -euo pipefail

# Basic render script for local dry-run/debugging
# Select cloud target: 'gcp' or 'azure'
CLOUD_TARGET=${1:-gcp} # Default to gcp, or take first argument

# --- Configuration (Simulate Cargo) ---
# Set environment variables or script arguments to define which environment
# and cloud to render.

# Example: Use cloud-specific cargo files based on CLOUD_TARGET
if [ "$CLOUD_TARGET" == "azure" ]; then
  TERRAFORM_HULL_DIR="terraform/hull-azure"
  TF_CARGO_FILE=${TF_CARGO_FILE:-terraform/cargo/azure-dev.tfvars.example}
  HELM_CARGO_FILE=${HELM_CARGO_FILE:-helm/cargo/azure-dev-overrides.yaml.example}
  # Ensure you are logged in via `az login` for local Azure TF operations
  echo "Targeting Azure. Ensure you have run 'az login' and set necessary ARM_* env vars if not using login."
elif [ "$CLOUD_TARGET" == "gcp" ]; then
  TERRAFORM_HULL_DIR="terraform/hull-gcp"
  TF_CARGO_FILE=${TF_CARGO_FILE:-terraform/cargo/dev.tfvars.example} # Keep original GCP example name
  HELM_CARGO_FILE=${HELM_CARGO_FILE:-helm/cargo/dev-overrides.yaml.example} # Keep original GCP example name
  # Ensure you are logged in via `gcloud auth application-default login`
  echo "Targeting GCP. Ensure you have run 'gcloud auth application-default login'."
else
    echo "Error: Invalid cloud target '$CLOUD_TARGET'. Use 'gcp' or 'azure'."
    exit 1
fi

HELM_CHART_PATH=${HELM_CHART_PATH:-helm/charts/example} # Chart path remains the same
HELM_RELEASE_NAME=${HELM_RELEASE_NAME:-${CLOUD_TARGET}-local-render}
HELM_NAMESPACE=${HELM_NAMESPACE:-my-namespace}

# --- Terraform Render (Plan) ---
echo "--- Rendering Terraform Plan for $CLOUD_TARGET --- "
(cd "${TERRAFORM_HULL_DIR}" && \
  terraform init -upgrade && \
  terraform plan -var-file="../../${TF_CARGO_FILE}" -out=local.tfplan
)
echo "Terraform plan saved to ${TERRAFORM_HULL_DIR}/local.tfplan"

# --- Helm Render (Template) ---
echo "\n--- Rendering Helm Template using $HELM_CARGO_FILE --- "
helm template "${HELM_RELEASE_NAME}" "./${HELM_CHART_PATH}" \
  -f ./helm/hull/values.yaml \
  -f "./${HELM_CARGO_FILE}" \
  --namespace "${HELM_NAMESPACE}" \
  --create-namespace > rendered-helm-${CLOUD_TARGET}.yaml
echo "Rendered Helm manifest saved to rendered-helm-${CLOUD_TARGET}.yaml"

echo "\nRender complete for $CLOUD_TARGET." 