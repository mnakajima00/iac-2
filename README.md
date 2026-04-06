PROMPT 2 — Local modules, intermediate team, GKE microservices platform

You are a platform engineer at a 20-person SaaS company called Brightwave.
Your team has used Terraform for 2.5 years. You inherited the original flat
repo from the founding engineer and have been gradually extracting modules
when you have time. The repo is mid-refactor — some things are modules, some
are still in root. Generate a realistic Terraform repository for Brightwave's
GCP infrastructure.

INFRASTRUCTURE:

- GKE Autopilot cluster
- 3 Cloud Run services: api-gateway, user-service, billing-service
- Cloud SQL PostgreSQL (shared across services, private IP)
- Memorystore Redis (session cache)
- Pub/Sub topic + subscription (billing events)
- Secret Manager (per-service secrets)
- VPC with private subnet + Cloud NAT
- Workload Identity bindings per service
- Artifact Registry

CODE STYLE:
Root module + ./modules/ directory containing:
modules/networking/ (VPC, subnet, NAT, firewall)
modules/gke/ (cluster, workload identity)
modules/database/ (Cloud SQL, private service access)

The 3 Cloud Run services and Pub/Sub are still in root main.tf because
you haven't gotten around to modularising them yet. Modules are called from
root main.tf. Module outputs are used as inputs to root-level resources.

MANDATORY STRESS TESTS — both must appear naturally:

1. Module output chain:
   module "networking" outputs network_id and subnet_id
   module "gke" takes network_id and subnet_id as inputs
   module "database" takes network_id as input
   Root-level Cloud Run services reference module.networking.vpc_connector_id
   — the parser must trace module.networking.output → Cloud Run attribute

2. Dynamic block on Cloud Run env vars:
   variable "api_env_vars" { type = map(string) }
   resource "google_cloud_run_v2_service" "api_gateway" {
   template {
   containers {
   dynamic "env" {
   for_each = var.api_env_vars
   content { name = env.key; value = env.value }
   }
   }
   }
   }

REALISM RULES:

- Company: brightwave
- modules/networking/main.tf has a comment at the top from 2022 that says
  "TODO: split into separate vpc and firewall modules" — never done
- Root main.tf has a mix of resource naming: some brightwave-prod-\*,
  some just descriptive names (api-gateway, user-service) without the prefix
  because the founding engineer named them before conventions existed
- Backend: GCS bucket = "brightwave-terraform-state", prefix = "prod"
- Provider version ~> 5.8 with a google-beta provider also configured
  for the GKE Autopilot resource
- modules/database/main.tf has a variable called enable_read_replica
  that is declared, has a default of false, and is never set to true
  anywhere — added speculatively, never used
- The billing-service Cloud Run resource has a depends_on pointing at
  the Pub/Sub topic even though Terraform could infer it — added by
  someone debugging a race condition and never removed
- terraform.tfvars exists at root with project_id, region, and
  api_env_vars populated with realistic-looking non-secret values

DO NOT add comments explaining resources. DO NOT add a README.
Resource names must look like real product infrastructure, not demos.

OUTPUT: Full file contents for every file in the repo.
Label each: === FILE: main.tf === / === FILE: modules/networking/main.tf === etc.
