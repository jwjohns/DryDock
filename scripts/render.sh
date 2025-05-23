#!/bin/bash
set -euo pipefail

# Basic render script for local dry-run/debugging
#
# Usage:
#   ./scripts/render.sh [gcp|azure] [-v|--validate-cargo]
#
# Arguments:
#   [gcp|azure]: Optional. Cloud target. Defaults to 'gcp'.
#   -v, --validate-cargo: Optional. If provided, validates the cargo files before rendering.

VALIDATE_CARGO_FLAG=false
CLOUD_TARGET=""

# Argument parsing
while (( "$#" )); do
  case "$1" in
    -v|--validate-cargo)
      VALIDATE_CARGO_FLAG=true
      shift
      ;;
    gcp|azure)
      if [ -n "$CLOUD_TARGET" ]; then
        echo "Error: Cloud target already set to '$CLOUD_TARGET'. Cannot specify multiple cloud targets."
        exit 1
      fi
      CLOUD_TARGET=$1
      shift
      ;;
    *) # preserve unknown arguments
      # This basic parsing assumes cloud target and flag are the primary arguments.
      # If other arguments were needed, a more robust getopts loop would be better.
      echo "Error: Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Set default cloud target if not provided
if [ -z "$CLOUD_TARGET" ]; then
  CLOUD_TARGET="gcp"
fi

# --- Paths ---
VALIDATOR_SCRIPT_PATH="$(dirname "$0")/local_dev/validate_cargo.sh"
LOCAL_TF_SECRETS_FILE="terraform/cargo/secrets.auto.tfvars" # Relative to repo root
LOCAL_HELM_SECRETS_FILE="helm/cargo/secrets.yaml"       # Relative to repo root


# --- Configuration (Simulate Cargo) ---
# Set environment variables or script arguments to define which environment
# and cloud to render.

# Example: Use cloud-specific cargo files based on CLOUD_TARGET
if [ "$CLOUD_TARGET" == "azure" ]; then
  TERRAFORM_HULL_DIR="terraform/hull-azure"
  TF_CARGO_FILE=${TF_CARGO_FILE:-terraform/cargo/azure-dev.tfvars.example}
  HELM_CARGO_FILE=${HELM_CARGO_FILE:-helm/cargo/azure-dev.override.yaml.example} # Corrected filename
  # Ensure you are logged in via `az login` for local Azure TF operations
  echo "Targeting Azure. Ensure you have run 'az login' and set necessary ARM_* env vars if not using login."
elif [ "$CLOUD_TARGET" == "gcp" ]; then
  TERRAFORM_HULL_DIR="terraform/hull-gcp"
  TF_CARGO_FILE=${TF_CARGO_FILE:-terraform/cargo/dev.tfvars.example}
  HELM_CARGO_FILE=${HELM_CARGO_FILE:-helm/cargo/dev.overrides.yaml.example}
  # Ensure you are logged in via `gcloud auth application-default login`
  echo "Targeting GCP. Ensure you have run 'gcloud auth application-default login'."
else
    # This case should ideally not be reached due to earlier parsing, but good for safety.
    echo "Error: Invalid cloud target '$CLOUD_TARGET'. Use 'gcp' or 'azure'."
    exit 1
fi

HELM_CHART_PATH=${HELM_CHART_PATH:-helm/charts/example}
HELM_RELEASE_NAME=${HELM_RELEASE_NAME:-${CLOUD_TARGET}-local-render}
HELM_NAMESPACE=${HELM_NAMESPACE:-my-namespace}

# --- Cargo Validation (Optional) ---
if [ "$VALIDATE_CARGO_FLAG" = true ]; then
  if [ ! -f "$VALIDATOR_SCRIPT_PATH" ]; then
    echo "Error: Validator script not found at $VALIDATOR_SCRIPT_PATH"
    exit 1
  fi
  echo "--- Validating Terraform cargo file: ${TF_CARGO_FILE}... ---"
  if ! "${VALIDATOR_SCRIPT_PATH}" "${CLOUD_TARGET}" "dev" "tfvars" "${TF_CARGO_FILE}"; then
    echo "Error: Terraform cargo file validation failed for ${TF_CARGO_FILE}."
    exit 1
  fi
  echo "Terraform cargo validation successful."

  echo "--- Validating Helm cargo file: ${HELM_CARGO_FILE}... ---"
  if ! "${VALIDATOR_SCRIPT_PATH}" "${CLOUD_TARGET}" "dev" "helm" "${HELM_CARGO_FILE}"; then
    echo "Error: Helm cargo file validation failed for ${HELM_CARGO_FILE}."
    exit 1
  fi
  echo "Helm cargo validation successful."
fi

# --- Terraform Render (Plan) ---
echo "--- Rendering Terraform Plan for $CLOUD_TARGET --- "
TF_SECRETS_ARG=""
# Path to LOCAL_TF_SECRETS_FILE is relative to TERRAFORM_HULL_DIR for the -var-file argument
TF_SECRETS_FILE_RELATIVE_TO_HULL_DIR="../../${LOCAL_TF_SECRETS_FILE}"
if [ -f "${TERRAFORM_HULL_DIR}/${TF_SECRETS_FILE_RELATIVE_TO_HULL_DIR}" ]; then
  TF_SECRETS_ARG="-var-file=${TF_SECRETS_FILE_RELATIVE_TO_HULL_DIR}"
  echo "Using local Terraform secrets file: ${TF_SECRETS_FILE_RELATIVE_TO_HULL_DIR}"
fi

(cd "${TERRAFORM_HULL_DIR}" && \
  terraform init -upgrade && \
  terraform plan -var-file="../../${TF_CARGO_FILE}" ${TF_SECRETS_ARG} -out=local.tfplan
)
echo "Terraform plan saved to ${TERRAFORM_HULL_DIR}/local.tfplan"

# --- Helm Render (Template) ---
echo "\n--- Rendering Helm Template using $HELM_CARGO_FILE --- "
HELM_SECRETS_ARG=""
# Path to LOCAL_HELM_SECRETS_FILE is relative to repo root
if [ -f "./${LOCAL_HELM_SECRETS_FILE}" ]; then
  HELM_SECRETS_ARG="-f ./${LOCAL_HELM_SECRETS_FILE}"
  echo "Using local Helm secrets file: ./${LOCAL_HELM_SECRETS_FILE}"
fi

helm template "${HELM_RELEASE_NAME}" "./${HELM_CHART_PATH}" \
  -f ./helm/hull/values.yaml \
  -f "./${HELM_CARGO_FILE}" \
  ${HELM_SECRETS_ARG} \
  --namespace "${HELM_NAMESPACE}" \
  --create-namespace > rendered-helm-${CLOUD_TARGET}.yaml
echo "Rendered Helm manifest saved to rendered-helm-${CLOUD_TARGET}.yaml"

echo "\nRender complete for $CLOUD_TARGET."