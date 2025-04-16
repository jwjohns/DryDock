# **Drydock: Git-Native Deployments for Secure, Scalable Infrastructure**

*Separating the "Hull" (Static Infrastructure) from the "Cargo" (Dynamic Configuration)*

[![Build Status](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/deploy.yaml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/deploy.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Replace MIT with your license -->
[![GitHub issues](https://img.shields.io/github/issues/YOUR_ORG/YOUR_REPO)](https://github.com/YOUR_ORG/YOUR_REPO/issues)
[![GitHub Discussions](https://img.shields.io/github/discussions/YOUR_ORG/YOUR_REPO)](https://github.com/YOUR_ORG/YOUR_REPO/discussions)

---

## **Mission**

**Drydock** is an open source deployment framework designed to **separate static infrastructure ("the hull") from dynamic configuration and secrets ("the cargo")**, enabling secure, scalable, and reproducible deployments across any environment using:

- **GitHub Actions**  
- **Terraform**  
- **Helm**  
- **Workload Identity Federation (WIF)** (GCP-native, AWS/IAM support roadmap)

It's purpose-built for modern teams moving away from legacy Jenkins-based deploys, toward **zero-key, auditable, Git-native automation**.

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

## **Architecture**

```
.
├── .github/workflows/
│   └── deploy.yaml          # GitHub Actions pipeline
├── terraform/
│   ├── modules/             # Shared bones (infra templates)
│   ├── hull/                # Static infra configs
│   └── cargo/               # Dynamic env-specific tfvars pulled at runtime
├── helm/
│   ├── charts/              # Helm charts
│   ├── hull/                # Base values
│   └── cargo/               # Env overrides from secrets manager or GCS
└── scripts/
    └── render.sh            # Optional local render for dry-run/debug
```

---

## **Workflow**

1. **Commit** static templates (Helm & Terraform modules) to GitHub
2. **Trigger** GitHub Actions on push or tag
3. **Authenticate** via WIF to GCP using OIDC token (no service account keys)
4. **Pull runtime config** from:
   - GCP Secret Manager
   - GCS
   - Optional Vault or SSM in future
5. **Render manifests**
6. **Deploy using `terraform apply` and `helm upgrade`**

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

Want the next steps?  
I can generate:
- A working example repo with `terraform + helm + gha + wif`
- GitHub Actions templates  
- Drydock CLI scaffold  
- Branding elements/logos if you want it to stand out on GitHub