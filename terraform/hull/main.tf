terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }

  # Backend configuration - uncomment and configure for actual state management
  # backend "gcs" {
  #   bucket  = "your-terraform-state-bucket-name" # <-- REPLACE THIS
  #   prefix  = "drydock/hull/state"
  # }
}

provider "google" {
  # Configuration for the Google provider.
  # When running in GitHub Actions with WIF, credentials are automatically sourced.
  # For local execution (like render.sh), you might need to set:
  # project = var.project_id
  # region  = var.region
  # zone    = var.zone
  # Or authenticate using `gcloud auth application-default login`
}

# --- Variables --- #
variable "project_id" {
  description = "The GCP Project ID to deploy resources into."
  type        = string
  # Consider loading this from cargo/env files or environment variables
}

variable "region" {
  description = "The primary GCP region for resources."
  type        = string
  # Example: default = "us-central1"
}

variable "zone" {
  description = "The primary GCP zone for resources."
  type        = string
  # Example: default = "us-central1-a"
}

# --- Resources defined in the Hull --- #

# Example: Define shared infrastructure here, like VPC networks, GKE clusters, IAM policies etc.
# This is the 'static' part of your infrastructure.

# We'll add modules and resources here in subsequent steps.
# For instance, we might add a GKE cluster definition:
# module "gke_cluster" {
#   source = "../modules/gke_cluster" # Assuming a module exists
#   project_id = var.project_id
#   region     = var.region
#   ...
# }

# Remove the leftover output from the dummy module
# output "example_bucket_name" {
#   description = "Name of the example GCS bucket created."
#   value       = module.example_bucket.bucket_name
# } 