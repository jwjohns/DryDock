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

# --- Networking --- #
resource "google_compute_network" "vpc_network" {
  project                 = var.project_id
  name                    = "drydock-gcp-network" # Consider parameterizing name via cargo
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  project                  = var.project_id
  name                     = "drydock-gcp-subnet" # Consider parameterizing name
  ip_cidr_range            = "10.10.0.0/20"     # Example CIDR - Choose appropriate range
  region                   = var.region
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = true

  # Define secondary ranges if needed for GKE Pods/Services
  # secondary_ip_range {
  #   range_name    = "gke-pods-range"
  #   ip_cidr_range = "10.20.0.0/16"
  # }
  # secondary_ip_range {
  #   range_name    = "gke-services-range"
  #   ip_cidr_range = "10.30.0.0/16"
  # }
}

# --- GKE Cluster --- #
resource "google_container_cluster" "primary" {
  project       = var.project_id
  name          = "drydock-gcp-cluster" # Consider parameterizing name
  location      = var.region          # Use regional cluster for higher availability
  # zone = var.zone # Use zone for zonal cluster

  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnet.name

  initial_node_count = 1 # Start with a small default node pool
  remove_default_node_pool = true # Recommended to manage node pools explicitly

  # Enable Workload Identity (Requires IAM setup - see below)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Other recommended settings:
  # logging_service = "logging.googleapis.com/kubernetes"
  # monitoring_service = "monitoring.googleapis.com/kubernetes"
  # networking_mode = "VPC_NATIVE"
  # ip_allocation_policy {
  #   cluster_secondary_range_name  = google_compute_subnetwork.subnet.secondary_ip_range[0].range_name
  #   services_secondary_range_name = google_compute_subnetwork.subnet.secondary_ip_range[1].range_name
  # }
  # private_cluster_config {
  #   enable_private_nodes    = true
  #   enable_private_endpoint = false # Or true if needed
  #   master_ipv4_cidr_block  = "172.16.0.0/28" # Example CIDR
  # }
  # master_authorized_networks_config { }

  # IMPORTANT: Add specific node pool definitions using google_container_node_pool
}

resource "google_container_node_pool" "primary_nodes" {
  project    = var.project_id
  name       = "default-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1 # Adjust as needed

  node_config {
    machine_type = "e2-medium" # Choose appropriate machine type
    # Specify the service account for WIF if needed, or use default GKE SA
    # service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# --- IAM for WIF (Example - Requires More Detail) --- #
# You need to grant the GitHub Actions WIF Service Account permissions
# to impersonate the Kubernetes Service Accounts used by your workloads.
# Example: Granting roles/iam.workloadIdentityUser role

# resource "google_service_account_iam_member" "wif_binding" {
#   provider = google-beta # Often needed for WIF features
#   service_account_id = "projects/${var.project_id}/serviceAccounts/your-k8s-sa@${var.project_id}.iam.gserviceaccount.com"
#   role               = "roles/iam.workloadIdentityUser"
#   member             = "serviceAccount:${var.project_id}.svc.id.goog[your-k8s-namespace/your-k8s-sa-name]"
# }

# You also need to grant the GHA Service Account (the one configured in deploy.yaml)
# roles needed to manage the resources defined above (e.g., roles/container.admin, roles/compute.networkAdmin)
# These bindings are typically done outside this TF config or via a separate higher-privilege run.

# --- Outputs (Optional) --- #
output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "network_name" {
  description = "VPC Network name"
  value       = google_compute_network.vpc_network.name
} 