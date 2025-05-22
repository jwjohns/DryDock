# Migrating from Jenkins to Drydock

This guide helps you transition your CI/CD pipelines from traditional Jenkins setups to the modern, Git-native, and Workload Identity Federation (WIF)-based approach of Drydock on GitHub Actions. Migrating can seem daunting, but by understanding the core differences and mapping your existing concepts to the new model, you can achieve a more secure, scalable, and maintainable CI/CD process.

Drydock leverages GitHub Actions, Terraform, and Helm, with a strong emphasis on WIF to eliminate the need for long-lived cloud provider secrets in your CI/CD environment.

## Table of Contents
* [Introduction](#introduction)
* [Core Philosophy Shift](#core-philosophy-shift)
* [Key Migration Areas](#key-migration-areas)
    * [1. Migrating Credentials and Secrets: The WIF Approach](#1-migrating-credentials-and-secrets-the-wif-approach)
        * [Jenkins Credential Handling](#jenkins-credential-handling)
        * [Drydock's WIF and Cloud Vault Strategy](#drydocks-wif-and-cloud-vault-strategy)
        * [Mapping Jenkins Credentials to Drydock/WIF](#mapping-jenkins-credentials-to-drydockwif)
    * [2. Converting Jenkins Jobs/Pipelines to GitHub Actions Workflows](#2-converting-jenkins-jobspipelines-to-github-actions-workflows)
        * [Jenkins Job Types (Freestyle, Pipeline)](#jenkins-job-types-freestyle-pipeline)
        * [GitHub Actions Workflows as the Equivalent](#github-actions-workflows-as-the-equivalent)
        * [Translating `Jenkinsfile` (Declarative/Scripted) to Workflow YAML](#translating-jenkinsfile-declarativescripted-to-workflow-yaml)
    * [3. Handling Parameters and Triggers](#3-handling-parameters-and-triggers)
        * [Jenkins Parameters and Triggers](#jenkins-parameters-and-triggers)
        * [Drydock/GitHub Actions Equivalents (`workflow_dispatch`, `on:`, event payloads)](#drydockgithub-actions-equivalents-workflow_dispatch-on-event-payloads)
    * [4. Managing Agents and Environments](#4-managing-agents-and-environments)
        * [Jenkins Agents and Labels](#jenkins-agents-and-labels)
        * [GitHub Actions Runners (Hosted & Self-Hosted)](#github-actions-runners-hosted--self-hosted)
        * [Tooling and Dependencies](#tooling-and-dependencies)
        * [Defining Deployment Environments (Dev, Staging, Prod)](#defining-deployment-environments-dev-staging-prod)
    * [5. Artifacts and Dependencies](#5-artifacts-and-dependencies)
        * [Jenkins Artifact Archiving](#jenkins-artifact-archiving)
        * [GitHub Actions Artifacts](#github-actions-artifacts)
        * [Managing External Dependencies](#managing-external-dependencies)
    * [6. Approvals and Gates](#6-approvals-and-gates)
        * [Jenkins `input` Step and Approval Plugins](#jenkins-input-step-and-approval-plugins)
        * [GitHub Actions Environments and Required Reviewers](#github-actions-environments-and-required-reviewers)
    * [7. Environment Variables](#7-environment-variables)
        * [Injecting Environment Variables in Jenkins](#injecting-environment-variables-in-jenkins)
        * [Environment Variables in GitHub Actions (env context, secrets)](#environment-variables-in-github-actions-env-context-secrets)
    * [8. Shared Libraries and Reusable Code](#8-shared-libraries-and-reusable-code)
        * [Jenkins Shared Libraries](#jenkins-shared-libraries)
        * [GitHub Actions Reusable Workflows and Custom Actions](#github-actions-reusable-workflows-and-custom-actions)
* [General Migration Strategy: Step-by-Step Considerations](#general-migration-strategy-step-by-step-considerations)
    * [1. Inventory and Analyze Existing Jenkins Setup](#1-inventory-and-analyze-existing-jenkins-setup)
    * [2. Plan Secret Migration to Cloud Vaults](#2-plan-secret-migration-to-cloud-vaults)
    * [3. Design Your GitHub Actions Workflow Structure](#3-design-your-github-actions-workflow-structure)
    * [4. Incremental Migration and Testing](#4-incremental-migration-and-testing)
    * [5. Decommissioning Jenkins (The Final Step)](#5-decommissioning-jenkins-the-final-step)
* [Troubleshooting and Common Pitfalls](#troubleshooting-and-common-pitfalls)
* [Conclusion](#conclusion)

## Core Philosophy Shift

Understanding the fundamental differences in approach is crucial for a successful migration:

*   **Secret Management: Key-based vs. WIF**
    *   **Jenkins:** Often relies on storing long-lived credentials (API keys, service account JSON files, SSH keys) directly within Jenkins or an integrated vault. This can pose security risks if Jenkins is compromised or if keys are not rotated regularly.
    *   **Drydock:** Emphasizes Workload Identity Federation (WIF). Your GitHub Actions workflow authenticates to cloud providers (GCP, Azure) by exchanging a short-lived OIDC token for a cloud provider access token. This means no long-lived cloud secrets are stored in GitHub. Application-level secrets are managed in dedicated cloud vaults (GCP Secret Manager, Azure Key Vault) and fetched at runtime using the WIF-acquired identity.

*   **Pipeline Definition: Imperative/Groovy vs. Declarative/YAML**
    *   **Jenkins:** `Jenkinsfile` pipelines, especially Scripted Pipelines, offer a lot of Groovy programming flexibility, which can be powerful but also complex and harder to standardize.
    *   **Drydock/GitHub Actions:** Workflows are defined in YAML. While `run` steps allow scripting, the overall structure is more declarative, promoting consistency and easier understanding.

*   **Infrastructure: Mutable vs. Immutable (Conceptual)**
    *   **Jenkins:** Can be used for both immutable infrastructure deployments and direct modifications to existing mutable environments.
    *   **Drydock:** While flexible, the "Hull" (static infrastructure) and "Cargo" (dynamic configuration) philosophy encourages treating infrastructure components more immutably. Changes are versioned in Git and rolled out through the pipeline.

*   **Centralized vs. Repository-Centric CI/CD**
    *   **Jenkins:** Often a centralized CI/CD server (or cluster) managing many projects. Configuration can be split between the Jenkins UI and `Jenkinsfile`s.
    *   **Drydock/GitHub Actions:** CI/CD configuration (`.github/workflows/`) lives directly within each repository. This empowers teams to manage their own deployment processes more directly, though it requires a different governance model.

## Key Migration Areas

### 1. Migrating Credentials and Secrets: The WIF Approach

This is often the most critical and beneficial part of the migration.

#### Jenkins Credential Handling
In Jenkins, you might be using:
*   The built-in Jenkins Credentials store (global, folder-scoped) for usernames/passwords, secret text, SSH keys, or "secret files" like GCP service account JSON keys.
*   Plugins like the HashiCorp Vault Plugin to fetch secrets dynamically.
*   Environment variables injected with secrets.

The common denominator is that Jenkins often becomes a direct holder or a direct broker of long-lived sensitive credentials.

#### Drydock's WIF and Cloud Vault Strategy
Drydock fundamentally changes this by leveraging Workload Identity Federation and external cloud-native secret vaults:

*   **Workload Identity Federation (WIF):**
    *   Your GitHub Actions workflow authenticates to GCP or Azure using an OIDC token. This token is exchanged for a short-lived access token from the cloud provider.
    *   **No long-lived cloud keys (e.g., GCP SA keys, Azure Client Secrets for SPs) are stored in GitHub.**
    *   Configuration for WIF (like provider IDs, service account emails to impersonate, Azure application client IDs) is stored as GitHub Secrets. These are configurations, not the actual secrets of your cloud resources.
*   **Cloud-Native Secret Vaults (GCP Secret Manager, Azure Key Vault):**
    *   **Application-level secrets** (e.g., database passwords, API keys for third-party services, TLS certificates) should be stored in these vaults.
    *   The Drydock workflow, once authenticated via WIF, fetches these secrets at runtime.
    *   The fetched secrets are made available to Terraform and Helm as temporary files (`secrets.auto.tfvars`, `secrets.yaml`) in the runner, which are cleaned up automatically. (Refer to `USAGE.md` for how to configure this).

#### Mapping Jenkins Credentials to Drydock/WIF

*   **GCP Service Account JSON Keys:**
    *   **Jenkins:** Uploaded as a "Secret file" or path to the key on an agent.
    *   **Drydock:**
        1.  Configure WIF between your GCP project and your GitHub repository/organization.
        2.  Grant the GCP Service Account (that the key belonged to) the necessary IAM roles.
        3.  Store the WIF provider path and the SA email in GitHub Secrets (`GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT_EMAIL`). The workflow uses these to impersonate the SA.
        4.  Any application secrets previously accessed *by* this SA should now be stored in GCP Secret Manager and accessed by the SA (and thus by the workflow impersonating it).

*   **Azure Service Principal Credentials (Client ID/Secret or Certificates):**
    *   **Jenkins:** Stored as username/password (client ID/secret) or certificate credentials.
    *   **Drydock:**
        1.  Configure WIF by creating an Azure AD App Registration and federating it with your GitHub repository/organization.
        2.  Grant this App Registration (Service Principal) the necessary roles on Azure resources.
        3.  Store the Application (Client) ID, Tenant ID, and Subscription ID in GitHub Secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`). The workflow uses these for WIF login.
        4.  Application secrets go into Azure Key Vault, accessible by the Service Principal.

*   **Generic API Keys / Secret Text / Usernames & Passwords:**
    *   **Jenkins:** Stored as "Secret text" or "Username with password".
    *   **Drydock:**
        1.  Store these secrets in GCP Secret Manager or Azure Key Vault.
        2.  Configure the Drydock workflow (as per `USAGE.md`) to pull them into `secrets.auto.tfvars` (for Terraform) or `secrets.yaml` (for Helm).
        3.  Reference them in your Terraform configurations (e.g., as variables) or Helm charts (e.g., via `.Values`).

*   **SSH Keys (e.g., for accessing private Git repositories):**
    *   **Jenkins:** Stored as "SSH Username with private key".
    *   **Drydock/GitHub Actions:**
        1.  Store the private SSH key as a GitHub Secret.
        2.  In a workflow step, use an action like `webfactory/ssh-agent@v0.8.0` or manually add the key to the ssh-agent to make it available for Git operations or SSH commands.
        3.  For accessing other repositories during a workflow, consider using a GitHub App installation token or a Deploy Key if appropriate, which can sometimes avoid manual SSH key management.

Migrating secrets is paramount. The goal is to move away from storing long-lived keys in your CI system and instead rely on WIF for cloud authentication and a dedicated vault for application secrets, all orchestrated by GitHub Actions.

### 2. Converting Jenkins Jobs/Pipelines to GitHub Actions Workflows

Translating your Jenkins jobs or `Jenkinsfile` pipelines into GitHub Actions workflows is a core part of the migration.

#### Jenkins Job Types (Freestyle, Pipeline)
*   **Freestyle Jobs:** Configured primarily through the Jenkins UI. Steps might involve shell scripts, build tool invocations (Maven, Gradle), and post-build actions.
*   **Pipeline Jobs:** Defined using a `Jenkinsfile`, either in Declarative or Scripted syntax. These offer more complex logic, conditional execution, parallelism, and integration with Jenkins features like Shared Libraries.

#### GitHub Actions Workflows as the Equivalent
In GitHub Actions, the entire CI/CD process is defined in one or more YAML files located in the `.github/workflows/` directory of your repository. The Drydock project uses `deploy.yaml` as its main workflow file.

Key concepts in GitHub Actions workflows:
*   **Workflows:** The top-level definition, triggered by specific events.
*   **Events:** Activities that trigger a workflow (e.g., `push`, `pull_request`, `workflow_dispatch`, `schedule`).
*   **Jobs:** A set of steps that execute on the same runner. Jobs can run in parallel or depend on other jobs.
*   **Steps:** Individual tasks within a job. A step can be a `run` command (executing shell scripts) or a `uses` clause (referencing a reusable Action from the Marketplace or a custom action).
*   **Actions:** Reusable units of code. Many common tasks (checking out code, setting up SDKs, authenticating to cloud providers) are available as pre-built Actions. Drydock's workflow uses actions like `actions/checkout@v4`, `google-github-actions/auth@v2`, `azure/login@v1`, etc.

#### Translating `Jenkinsfile` (Declarative/Scripted) to Workflow YAML

*   **Overall Structure:**
    *   A `Jenkinsfile` (especially Declarative) often has `pipeline { agent {} stages {} post {} }`.
    *   A GitHub Actions workflow has `name:`, `on:`, `jobs: <job_name>: runs-on: steps: []`.
*   **Agent/Runner:**
    *   Jenkins `agent any` or `agent { label 'my-agent' }` maps to `jobs.<job_name>.runs-on: ubuntu-latest` (or other hosted runners, or self-hosted runner labels).
*   **Stages and Steps:**
    *   Jenkins `stage('Build') { steps { sh './build.sh' } }` maps to a job or a series of named steps within a job:
      ```yaml
      jobs:
        deploy:
          runs-on: ubuntu-latest
          steps:
            - name: Checkout code
              uses: actions/checkout@v4
            - name: Build
              run: ./build.sh
            # Other steps for deploy, test etc.
      ```
    *   The Drydock `deploy.yaml` has a single `deploy` job with many sequential steps for setup, auth, cargo pulling, linting, Terraform, and Helm operations.
*   **Scripting (`sh`, `bat`, `pwsh`, Groovy):**
    *   Jenkins `sh 'echo "hello"'` or extensive Groovy logic within `script {}` blocks.
    *   GitHub Actions: Use `run:` steps. For multi-line scripts:
      ```yaml
      - name: Run a multi-line script
        run: |
          echo "First line"
          echo "Second line"
      ```
    *   Complex Groovy logic from Jenkins Scripted Pipelines often needs to be re-evaluated. Can it be simplified into shell scripts? Ported to Python? Or broken into smaller, reusable custom Actions if truly complex? Direct Groovy execution isn't native to GitHub Actions runners without specific setup.
*   **Conditional Execution:**
    *   Jenkins `when { expression { ... } }`.
    *   GitHub Actions: `if:` conditions on steps or jobs (e.g., `if: github.ref == 'refs/heads/main'`). The Drydock workflow uses `if: env.CLOUD_TARGET == 'gcp'` extensively.
*   **Parallelism:**
    *   Jenkins `parallel { stage(...) stage(...) }`.
    *   GitHub Actions: Define multiple jobs that don't have `needs:` dependencies on each other. They will run in parallel by default (up to account limits). For matrix builds (e.g., testing against multiple versions), use `jobs.<job_name>.strategy.matrix`.

### 3. Handling Parameters and Triggers

#### Jenkins Parameters and Triggers
*   **Parameters:** Defined via "This project is parameterized" (string, boolean, choice, etc.).
*   **Triggers:** SCM polling, push triggers (webhooks), upstream job completion, manual ("Build with Parameters"), timed (cron).

#### Drydock/GitHub Actions Equivalents (`workflow_dispatch`, `on:`, event payloads)
*   **Triggers (`on:`):**
    *   `on: push: branches: [main]` (for pushes to main).
    *   `on: pull_request: branches: [main]` (for PRs targeting main).
    *   `on: schedule: - cron: '0 0 * * *'` (for timed execution).
    *   `on: workflow_dispatch:` (for manual triggers). This is used by Drydock.
*   **Parameters (`workflow_dispatch.inputs`):**
    *   For manual triggers, define inputs in the `workflow_dispatch` section:
      ```yaml
      on:
        workflow_dispatch:
          inputs:
            cloud:
              description: 'Target cloud provider'
              required: true
              default: 'gcp'
              type: choice
              options:
                - gcp
                - azure
            environment:
              description: 'Deployment environment'
              required: true
              default: 'dev'
              type: string
      ```
    *   These are accessed via `github.event.inputs.<input_name>`, as seen in Drydock's `env.CLOUD_TARGET` and `env.ENV_TARGET` setup.
*   **Accessing Event Data:** For non-manual triggers, information like branch name, commit SHA, etc., is available in the `github` context (e.g., `github.ref`, `github.sha`).

### 4. Managing Agents and Environments

#### Jenkins Agents and Labels
*   Jenkins uses a master/agent architecture. Jobs can be assigned to specific agents using labels. Agents require setup with necessary tools (Java, Maven, Docker, etc.).

#### GitHub Actions Runners (Hosted & Self-Hosted)
*   **GitHub-Hosted Runners:** Maintained by GitHub, available with various operating systems (Ubuntu, Windows, macOS) and a wide array of pre-installed software. Specified with `runs-on: ubuntu-latest`, etc. Drydock uses `ubuntu-latest`.
*   **Self-Hosted Runners:** You can host your own runners for more control over hardware, software, networking (e.g., access to private resources), and security.

#### Tooling and Dependencies
*   **Jenkins:** Tools often pre-installed on agents or installed via "Tool Installers" (e.g., JDK, Maven).
*   **GitHub Actions:**
    *   Many tools are pre-installed on GitHub-hosted runners.
    *   Use setup actions for specific versions or tools not present: `actions/setup-java`, `actions/setup-python`, `google-github-actions/setup-gcloud`, `azure/setup-helm`, `hashicorp/setup-terraform` (all used in Drydock).
    *   Install other tools via `run` steps (e.g., `sudo apt-get install mytool`).

#### Defining Deployment Environments (Dev, Staging, Prod)
*   **Jenkins:** Often managed via job naming conventions, parameters, or separate jobs per environment. Promotion between environments can be manual or automated.
*   **Drydock/GitHub Actions:**
    *   **Environments Feature:** GitHub Actions offers "Environments" (e.g., `dev`, `staging`, `production`).
        *   Can have protection rules (e.g., required reviewers for approvals, wait timers).
        *   Can store environment-specific secrets and variables.
        *   Jobs can target specific environments: `jobs.<job_name>.environment: name: production`.
    *   **Drydock's Approach:** Uses the `environment` input to dynamically configure paths for cargo files (e.g., `dev.tfvars`, `prod.tfvars`). This allows a single workflow to deploy to multiple environments. Integrating with GitHub Environments for approvals would be a further enhancement.

### 5. Artifacts and Dependencies

#### Jenkins Artifact Archiving
*   Jenkins jobs can archive artifacts (build outputs like JARs, WARs, logs) using the "Archive the artifacts" post-build step. These are stored on the Jenkins master or external storage.

#### GitHub Actions Artifacts
*   **`actions/upload-artifact` and `actions/download-artifact`:** These actions allow you to persist files created during a job and share them with other jobs in the same workflow (or download them via UI/API).
*   **Storage:** Artifacts are stored in GitHub for a configurable retention period.
*   **Drydock Context:** Drydock primarily focuses on deploying infrastructure and configurations defined *as code*. While it could be extended to build and then deploy an application artifact, its current form doesn't explicitly deal with application build artifacts. If your Jenkins jobs build applications and then deploy them, you'd add build steps to the workflow and potentially upload the built artifact before the Terraform/Helm deployment steps.

#### Managing External Dependencies
*   **Jenkins:** Dependencies (e.g., Maven libraries, Node modules) are typically downloaded by the build tool during the job run.
*   **GitHub Actions:** Similar. Your build scripts (`mvn install`, `npm install`) run within the workflow steps and download dependencies as needed. Caching can be implemented using `actions/cache` to speed up builds.

### 6. Approvals and Gates

#### Jenkins `input` Step and Approval Plugins
*   Jenkins Pipelines can use the `input` step to pause the pipeline and wait for manual confirmation.
*   Various plugins offer more sophisticated approval mechanisms, sometimes integrating with external systems.

#### GitHub Actions Environments and Required Reviewers
*   **GitHub Environments:** You can define environments (e.g., "production", "staging") in your repository settings.
*   **Protection Rules:** Environments can have protection rules, including "Required reviewers." When a job in a workflow targets an environment with this rule, the workflow will pause until an authorized reviewer approves it.
    ```yaml
    jobs:
      deploy-to-prod:
        runs-on: ubuntu-latest
        environment:
          name: production
          url: https://my-app.com # Optional: link to deployed app
        steps:
          - name: Deploy
            run: echo "Deploying to production..."
    ```
*   **Manual `workflow_dispatch`:** Can also serve as a manual gate before any deployment actions occur.

### 7. Environment Variables

#### Injecting Environment Variables in Jenkins
*   Jenkins allows defining environment variables globally, at the node/agent level, or within a pipeline using the `environment {}` block (Declarative) or `withEnv([]) {}` (Scripted).
*   Secrets are often injected as environment variables.

#### Environment Variables in GitHub Actions (env context, secrets)
*   **`env` Context:** Set environment variables at the workflow, job, or step level:
    ```yaml
    name: My Workflow
    env:
      WORKFLOW_VAR: "workflow-level"
    jobs:
      my_job:
        env:
          JOB_VAR: "job-level"
        steps:
          - name: My Step
            env:
              STEP_VAR: "step-level"
            run: |
              echo "Workflow var: $WORKFLOW_VAR"
              echo "Job var: $JOB_VAR"
              echo "Step var: $STEP_VAR"
    ```
*   **GitHub Secrets:** All configured GitHub Secrets are automatically available as environment variables with the same name (e.g., a secret named `MY_API_KEY` is available as `$MY_API_KEY`). This is the primary way sensitive values are exposed to scripts.
*   **Setting Variables Dynamically:** Use `echo "VAR_NAME=value" >> $GITHUB_ENV` to make an environment variable available to subsequent steps in the same job. Drydock uses this in the "Set Cargo File Paths" step.

### 8. Shared Libraries and Reusable Code

#### Jenkins Shared Libraries
*   Jenkins allows defining Shared Libraries (typically Groovy scripts) in external Git repositories. These provide reusable functions and pipeline steps, promoting consistency and reducing code duplication in `Jenkinsfile`s.

#### GitHub Actions Reusable Workflows and Custom Actions
*   **Reusable Workflows (`workflow_call`):**
    *   Define a workflow that can be called by other workflows.
    *   Allows passing inputs and secrets.
    *   Excellent for standardizing deployment processes or common sequences of steps.
    *   Example: You could have a reusable workflow for "Terraform Plan & Apply" and another for "Helm Deploy."
*   **Custom Actions:**
    *   Develop your own actions if you have complex or highly reusable logic that doesn't fit well into simple script steps.
    *   Can be written in JavaScript (running in Node.js) or as Docker container actions, or as Composite run steps (YAML).
    *   Can be stored within the same repository (`./.github/actions/my-action`) or in a separate public/private repository.
*   **Scripts in the Repository:** For simpler reusable logic, maintain scripts (shell, Python, etc.) in your repository and call them from `run` steps in your workflow. Drydock's `scripts/render.sh` is an example, though used locally.

## General Migration Strategy: Step-by-Step Considerations

Migrating from Jenkins to Drydock/GitHub Actions is a project. Here's a general approach:

### 1. Inventory and Analyze Existing Jenkins Setup
*   List all Jenkins jobs/pipelines you intend to migrate.
*   For each job, document:
    *   Its purpose and triggers.
    *   Parameters it uses.
    *   Credentials and secrets it accesses.
    *   Agents/nodes it runs on and any specific tooling requirements.
    *   Key steps and scripts it executes.
    *   How it handles artifacts and downstream jobs.
    *   Any Shared Libraries it depends on.

### 2. Plan Secret Migration to Cloud Vaults
*   Identify all secrets currently managed by Jenkins.
*   Prioritize moving these into GCP Secret Manager or Azure Key Vault.
*   Plan the necessary WIF setup in GCP/Azure and configure the initial set of GitHub Secrets for Drydock (WIF provider IDs, SA emails, etc., as detailed in `USAGE.md`).

### 3. Design Your GitHub Actions Workflow Structure
*   Start with the Drydock `deploy.yaml` as a template.
*   Map your inventoried Jenkins job steps to GitHub Actions workflow steps.
*   Identify opportunities to use existing GitHub Marketplace Actions.
*   Determine if any complex Groovy logic needs to be rewritten as scripts or custom Actions.
*   Plan your environment strategy (e.g., using GitHub Environments for approvals).

### 4. Incremental Migration and Testing
*   **Start Small:** Migrate one or two simpler jobs first to gain experience.
*   **Parallel Run (Optional but Recommended):** For a critical pipeline, you might temporarily run both the old Jenkins job and the new GitHub Actions workflow in parallel to compare results and build confidence.
*   **Iterate:** Test thoroughly, review workflow logs, and refine your YAML.
*   **Cargo Files:** Set up your cargo files in cloud storage for different environments as you migrate corresponding deployment logic.

### 5. Decommissioning Jenkins (The Final Step)
*   Once you've successfully migrated and validated your workflows in GitHub Actions, and are confident in their stability and security, you can plan to disable or decommission the old Jenkins jobs.
*   Ensure all necessary monitoring and alerting are in place for your new GitHub Actions workflows.

## Troubleshooting and Common Pitfalls

*   **YAML Syntax:** GitHub Actions workflows are YAML-based. Pay close attention to indentation and syntax. Use a YAML validator or your IDE's linting features.
*   **Permissions for WIF:** Ensure the Service Account (GCP) or Managed Identity/Service Principal (Azure) that your workflow impersonates via WIF has the *least privilege* necessary to perform its tasks (e.g., read from Secret Manager, write to GCS, deploy to GKE/AKS). This is a common source of errors.
*   **Secret Naming in Vaults:** Double-check that the secret names in GCP Secret Manager / Azure Key Vault match what the Drydock workflow expects (see `USAGE.md`), especially the hyphen vs. period differences for Azure.
*   **Path Issues in `run` Steps:** Scripts in `run` steps execute from the root of your checked-out repository. Adjust paths accordingly.
*   **Differences in Shell Behavior:** Scripts that ran in Jenkins might behave slightly differently due to shell versions or available utilities on GitHub-hosted runners. Test scripts carefully.
*   **Debugging Workflow Issues:**
    *   Examine the detailed logs for each step in the GitHub Actions UI.
    *   Enable step debug logging by creating a secret named `ACTIONS_STEP_DEBUG` with the value `true`.
    *   Use actions like `tmate/tmate-action` to get an SSH session into the runner for live debugging (use with caution, especially with production workflows).

## Conclusion

Migrating from Jenkins to Drydock on GitHub Actions is an investment that pays off in enhanced security (via WIF), better version control of your CI/CD process (Git-native), and improved scalability and maintainability. By understanding the core differences and planning your migration methodically, you can leverage the full power of this modern deployment paradigm. Refer to the Drydock `README.md` and `USAGE.md` for specific configuration details of the Drydock workflow itself.
