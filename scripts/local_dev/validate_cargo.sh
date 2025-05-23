#!/bin/bash

# Purpose: Validates the format and structure of local cargo files for Drydock.
#
# Prerequisites:
# - For tfvars validation: terraform CLI installed.
# - For Helm YAML validation: yamllint (preferred) or python3.
#
# Usage:
#   ./scripts/local_dev/validate_cargo.sh <cloud_target> <env_name> <file_type> <file_path>
#
# Arguments:
#   <cloud_target>: 'gcp' or 'azure' (for context, not strictly used in validation logic yet)
#   <env_name>:     Environment name, e.g., 'dev', 'prod' (for context)
#   <file_type>:    'tfvars' for Terraform HCL files, or 'helm' for Helm YAML override files.
#   <file_path>:    Path to the local cargo file to validate.

set -euo pipefail

usage() {
  echo "Usage: $0 <cloud_target> <env_name> <file_type> <file_path>"
  echo ""
  echo "Arguments:"
  echo "  <cloud_target>: 'gcp' or 'azure' (contextual)"
  echo "  <env_name>:     Environment name, e.g., 'dev', 'prod' (contextual)"
  echo "  <file_type>:    'tfvars' (Terraform HCL) or 'helm' (Helm YAML override)"
  echo "  <file_path>:    Path to the local cargo file"
  echo ""
  echo "Example:"
  echo "  $0 gcp dev tfvars ./terraform/cargo/dev.tfvars.example"
  echo "  $0 azure dev helm ./helm/cargo/azure-dev-override.yaml.example"
  exit 1
}

# --- Input Parsing & Validation ---
if [ "$#" -ne 4 ]; then
  echo "Error: Incorrect number of arguments."
  usage
fi

CLOUD_TARGET="$1"
ENV_NAME="$2"
FILE_TYPE="$3"
FILE_PATH="$4"

if [[ "${CLOUD_TARGET}" != "gcp" && "${CLOUD_TARGET}" != "azure" ]]; then
  echo "Error: Invalid <cloud_target>. Must be 'gcp' or 'azure'."
  usage
fi

if [ ! -f "${FILE_PATH}" ]; then
  echo "Error: File not found at '${FILE_PATH}'"
  usage
fi

# --- Main Validation Logic ---

if [ "${FILE_TYPE}" == "tfvars" ]; then
  echo "--- Validating Terraform HCL (.tfvars) file: ${FILE_PATH} ---"
  if ! command -v terraform &> /dev/null; then
    echo "Error: terraform CLI not found. Please install Terraform."
    exit 1
  fi

  echo "Running: terraform fmt -check -diff \"${FILE_PATH}\""
  if terraform fmt -check -diff "${FILE_PATH}"; then
    echo "Terraform HCL format check passed for ${FILE_PATH}."
    exit 0
  else
    TF_EXIT_CODE=$?
    echo "Terraform HCL format check failed for ${FILE_PATH}. Output from terraform fmt is above."
    exit ${TF_EXIT_CODE}
  fi

elif [ "${FILE_TYPE}" == "helm" ]; then
  echo "--- Validating Helm YAML override file: ${FILE_PATH} ---"
  if command -v yamllint &> /dev/null; then
    echo "Using yamllint for validation."
    echo "Running: yamllint --strict \"${FILE_PATH}\""
    if yamllint --strict "${FILE_PATH}"; then
      echo "yamllint validation passed for ${FILE_PATH}."
      exit 0
    else
      YAMLLINT_EXIT_CODE=$?
      echo "yamllint validation failed for ${FILE_PATH}. Output from yamllint is above."
      exit ${YAMLLINT_EXIT_CODE}
    fi
  elif command -v python3 &> /dev/null; then
    echo "yamllint not found. Using python3 for basic YAML structure check."
    PYTHON_SCRIPT='
import yaml
import sys
try:
    with open(sys.argv[1], "r") as f:
        yaml.safe_load(f)
    # If no exception, YAML is parsable.
except Exception as e:
    print(f"Python YAML Parsing Error: {e}", file=sys.stderr)
    sys.exit(1)
'
    echo "Running: python3 -c \"<python_script>\" \"${FILE_PATH}\""
    if python3 -c "${PYTHON_SCRIPT}" "${FILE_PATH}"; then
      echo "Basic YAML structure check (via Python) passed for ${FILE_PATH}."
      exit 0
    else
      PYTHON_EXIT_CODE=$?
      echo "Basic YAML structure check (via Python) failed for ${FILE_PATH}. Python output is above."
      exit ${PYTHON_EXIT_CODE}
    fi
  else
    echo "Warning: yamllint and python3 not found. Skipping advanced YAML validation for ${FILE_PATH}."
    exit 0 # No validation performed, so not a failure of the validator itself.
  fi

else
  echo "Error: Invalid <file_type> '${FILE_TYPE}'. Must be 'tfvars' or 'helm'."
  usage
fi
