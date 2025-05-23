<p align="center">
  <img src="docs/logo.png" alt="Drydock Logo" width="150">
</p>

# **Drydock: Git-Native Deployments for Secure, Scalable Infrastructure**

*Separating the "Hull" (Static Infrastructure) from the "Cargo" (Dynamic Configuration) across **GCP and Azure**.*

[![Build Status](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/deploy.yaml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/deploy.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Replace MIT with your license -->
[![GitHub issues](https://img.shields.io/github/issues/YOUR_ORG/YOUR_REPO)](https://github.com/YOUR_ORG/YOUR_REPO/issues)
[![GitHub Discussions](https://img.shields.io/github/discussions/YOUR_ORG/YOUR_REPO)](https://github.com/YOUR_ORG/YOUR_REPO/discussions)

---

## **Mission**

**Drydock** is an open source deployment framework designed to **separate static infrastructure ("the hull") from dynamic configuration and secrets ("the cargo")**, enabling secure, scalable, and reproducible deployments across **GCP and Azure** (initially) using:

- **GitHub Actions**  
- **Terraform**  
- **Helm**  
- **Workload Identity Federation (WIF)** (GCP-native, AWS/IAM support roadmap)

It's purpose-built for modern teams moving away from legacy Jenkins-based deploys, toward **zero-key, auditable, Git-native automation**. For guidance on this transition, see our [Migrating from Jenkins Guide](MIGRATING_FROM_JENKINS.md).

---

## **Core Philosophy**

In a shipyard drydock, the hull is constructed before it's ever launched into water. **Drydock** adopts this metaphor:

- **The Hull** = statically defined, versioned infrastructure & Helm templates
- **The Cargo** = runtime values, secrets, and overrides injected at deployment time

---

## **Key Features**

- **Workload Identity Federation** to eliminate long-lived secrets in CI/CD
- **Environment-specific layering** with Terraform `.tfvars` and Helm overrides
- **Secure "flesh injection"** of runtime config at deploy-time only
- **GitHub Actions-first** with composable workflows
- **Support for fleet deployments** across stores, environments, or regions
- **Backwards-compatible with Jenkins era** through transitional CLI hooks

---

## Getting Started

To begin using Drydock, you first need to set up the necessary resources in your chosen cloud provider (GCP or Azure) to enable Workload Identity Federation, create storage for cargo files, and set up secret management.

We provide bootstrapping scripts to help automate this initial setup. Please refer to our:

- **[Drydock Bootstrapping Guide](BOOTSTRAPPING.md)**: For initial cloud environment setup.
- **[Local Development and Testing Guide](LOCAL_DEVELOPMENT.md)**: For tips on local testing and simulating the workflow.

Once your cloud environment is bootstrapped (see the Bootstrapping Guide) and you have configured the required GitHub Secrets, refer to the [Drydock Workflow Usage and Configuration Guide](USAGE.md) for details on running the deployment workflow and managing your cargo files.

---

## **Architecture**

```
.
├── .github/workflows/
│   └── deploy.yaml          # Multi-cloud GitHub Actions pipeline (GCP/Azure)
├── terraform/
│   ├── modules/             # Shared infra modules (cloud-agnostic or specific)
│   ├── hull-gcp/            # Static GCP infra configs (e.g., GKE, VPC)
│   ├── hull-azure/          # Static Azure infra configs (e.g., AKS, VNET)
│   └── cargo/               # Dynamic env-specific tfvars pulled at runtime
│       ├── dev.tfvars.example # GCP dev example
│       └── azure-dev.tfvars.example # Azure dev example
├── helm/
│   ├── charts/              # Helm charts (e.g., ./example)
│   ├── hull/                # Base Helm values (common defaults)
│   └── cargo/               # Env/Cloud specific Helm overrides
│       ├── dev-overrides.yaml.example # GCP dev example
│       └── azure-dev-overrides.yaml.example # Azure dev example
└── scripts/
    └── render.sh            # Optional local render for dry-run/debug (e.g., ./render.sh azure)
```

---

## **Workflow**

1. **Select Target:** Choose Cloud (`gcp` or `azure`) and Environment (`dev`, `prod`, etc.) via GitHub Actions manual trigger inputs (or use defaults for push triggers).
2. **Commit** static templates (Helm & Terraform modules/hulls) to GitHub.
3. **Trigger** GitHub Actions on push, tag, or manual dispatch.
4. **Authenticate** via WIF to the selected cloud (GCP or Azure) using OIDC token.
5. **Pull runtime config ("Cargo")** for the specific cloud/environment from sources like:
   - GCP Secret Manager / Azure Key Vault
   - GCS / Azure Blob Storage
6. **Render manifests** using fetched cargo files.
7. **Deploy using `terraform apply` (in the correct hull directory) and `helm upgrade`** against the target cluster (GKE or AKS).

For detailed instructions on configuring the necessary GitHub Secrets and setting up your cargo files in cloud storage, please see the [Drydock Workflow Usage and Configuration Guide](USAGE.md).

---

## **Security Model**

- No secrets stored in GitHub
- All secrets resolved at runtime via federated identity
- Per-environment isolation by design
- Optional secret caching for airgapped preview/test

---

## **Roadmap**

- [ ] AWS/Azure WIF support
- [ ] ArgoCD and Flux plug-ins
- [ ] Drydock CLI for local preview, secret validation
- [ ] Support for Kustomize
- [ ] Plugin system for loading secrets from HashiCorp Vault, Doppler, or SOPS

---

## **Why Drydock?**

Most teams hack this flow together in CI — Drydock makes it **a pattern, not a pile of scripts**. It's Git-native, secure, modular, and easy to adopt incrementally.

---
