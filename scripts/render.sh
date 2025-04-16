#!/bin/bash
set -euo pipefail

# Basic render script for local dry-run/debugging

# --- Configuration (Simulate Cargo) ---
# Set environment variables or script arguments to define which environment
# to render. For example:
# export TF_VAR_environment="dev"
# export HELM_OVERRIDES_FILE="helm/cargo/dev-overrides.yaml"

# Example: Default to 'dev' if not set
TF_CARGO_FILE=${TF_CARGO_FILE:-terraform/cargo/dev.tfvars.example}
HELM_CARGO_FILE=${HELM_CARGO_FILE:-helm/cargo/dev-overrides.yaml.example}
HELM_CHART_PATH=${HELM_CHART_PATH:-helm/charts/example}
HELM_RELEASE_NAME=${HELM_RELEASE_NAME:-my-local-render}
HELM_NAMESPACE=${HELM_NAMESPACE:-my-namespace}

# --- Terraform Render (Plan) ---
echo "--- Rendering Terraform Plan --- "
(cd terraform/hull && \
  terraform init -upgrade && \
  terraform plan -var-file="../../${TF_CARGO_FILE}" -out=local.tfplan
)
echo "Terraform plan saved to terraform/hull/local.tfplan"

# --- Helm Render (Template) ---
echo "\n--- Rendering Helm Template --- "
helm template "${HELM_RELEASE_NAME}" "./${HELM_CHART_PATH}" \
  -f ./helm/hull/values.yaml \
  -f "./${HELM_CARGO_FILE}" \
  --namespace "${HELM_NAMESPACE}" \
  --create-namespace > rendered-helm.yaml
echo "Rendered Helm manifest saved to rendered-helm.yaml"

echo "\nRender complete." 