# Infrastructure — Phase 5 (domain/08-phases.md)

Terraform modules + Terragrunt environments for deploying the API
([api/main.py](../api/main.py)) to Azure Container Apps. Follows the
Gruntwork-style split: **`modules/`** holds reusable, environment-agnostic
Terraform; **`live/`** holds Terragrunt configs that are pure environment
wiring (which module, with which inputs, in which environment) and contain no
Terraform logic of their own.

## Layout

```
infra/
├── bootstrap/              # one-time, manually-applied, local state (see below)
├── modules/                # reusable Terraform, no environment-specific values
│   ├── resource-group/
│   ├── log-analytics/
│   ├── container-registry/
│   ├── container-app-environment/
│   └── container-app/
└── live/
    ├── root.hcl            # remote state backend + provider, inherited by everything below
    └── dev/
        ├── env.hcl         # the ONLY file with dev-specific values (region, sizing, tags)
        ├── resource-group/terragrunt.hcl
        ├── log-analytics/terragrunt.hcl
        ├── container-registry/terragrunt.hcl
        ├── container-app-environment/terragrunt.hcl
        └── container-app/terragrunt.hcl
```

Adding a `staging` or `prod` environment later means copying `live/dev/` to
`live/staging/`, editing `env.hcl`, and nothing else — no module changes, no
duplicated Terraform.

## What's actually deployed (and what isn't)

Matches the minimal scope cut ([domain/07-scope-cutlines.md](../domain/07-scope-cutlines.md)):
one Container App running the FastAPI image, with its own Container Apps
Environment, an Azure Container Registry to host the image, and a Log
Analytics workspace for platform logs. No Event Hubs (batch ingestion, not
streaming), no Blob Storage (the DuckDB warehouse is baked into the Docker
image at build time — see [../Dockerfile](../Dockerfile)), no Key Vault
(env-var secrets, documented as a known gap in
[domain/06-security.md](../domain/06-security.md)).

## Security decisions worth calling out

- **No ACR admin credentials.** `azurerm_container_registry.admin_enabled = false`.
  The Container App authenticates to the registry via its own
  user-assigned managed identity, scoped to `AcrPull` on that one registry
  only (`modules/container-app/main.tf`) — least-privilege, no shared
  username/password floating around.
- **Secrets never touch the repo.** `ANTHROPIC_API_KEY`, `ANTHROPIC_WORKSPACE_ID`,
  and `API_KEY` flow from the operator's shell environment into Terragrunt via
  `get_env(...)` (`live/dev/container-app/terragrunt.hcl`) straight into Azure
  Container Apps' own secret store — the same variables the app already reads
  locally from `.env` ([.env.example](../.env.example)), never written to disk
  in this repo or to Terraform state in plaintext form beyond what
  `azurerm_container_app` itself requires.

## One-time bootstrap: Terraform remote state

Terragrunt's `remote_state` block in `live/root.hcl` points at an Azure Storage
Account for state — but that storage account has to exist before Terragrunt
can use it, and it can't be the thing that creates itself. `infra/bootstrap/`
is a small, separate Terraform config with **local** state, applied manually,
once, per subscription:

```bash
cd infra/bootstrap
terraform init
terraform apply
```

Its outputs (resource group, storage account, container name) must match the
hardcoded values in `live/root.hcl`'s `remote_state.config` block. This is
deliberately outside Terragrunt's management — see the comment at the top of
`infra/bootstrap/main.tf` for why.

## Deploying (once you have Azure credentials)

```bash
az login
# or: export ARM_CLIENT_ID=... ARM_CLIENT_SECRET=... ARM_TENANT_ID=... ARM_SUBSCRIPTION_ID=...

# 1. bootstrap the state backend (once per subscription)
cd infra/bootstrap && terraform init && terraform apply

# 2. build and push the image (container-registry must exist first)
cd infra/live/dev/container-registry && terragrunt apply
ACR_LOGIN_SERVER=$(terragrunt output -raw login_server)
docker build -t "$ACR_LOGIN_SERVER/port-intelligence-agent:latest" ../../../../..
az acr login --name "$(terragrunt output -raw name)"
docker push "$ACR_LOGIN_SERVER/port-intelligence-agent:latest"

# 3. bring up the rest of the stack, secrets from your shell env
export ANTHROPIC_API_KEY=...      # or ANTHROPIC_WORKSPACE_ID / API_KEY as needed
cd infra/live/dev
terragrunt run-all apply
```

`terragrunt run-all apply` resolves the dependency graph automatically
(resource group → log analytics + container registry → container app
environment → container app) via the `dependency` blocks in each component's
`terragrunt.hcl` — no manual ordering needed beyond pushing the image before
the container app first references it.

## What's verified as of this PoC (no real Azure account used)

- **Every module validates standalone**: `terraform init -backend=false && terraform validate`
  passes clean on all 5 modules and on `infra/bootstrap`.
- **The Terragrunt wiring is correct up to the Azure authentication
  boundary**: `terragrunt validate` on `live/dev/resource-group` resolves
  `include`, `env.hcl`, and the generated `provider.tf`/`backend.tf`
  correctly, and fails at exactly the point real cloud access would be
  needed (`az` CLI / `ARM_*` credentials not present in this environment) —
  not on a config error. That's the honest boundary of what can be verified
  without a real subscription; see [domain/08-phases.md](../domain/08-phases.md)
  for the plan to close it out with real credentials.
- **The Docker image builds and runs correctly**: `docker build` succeeds,
  the container starts, `/health` and the authenticated `/sap/PortCallSet`
  endpoint both respond correctly against the embedded DuckDB warehouse.

## Known gaps

- **OpenTelemetry's OTLP exporter target is `localhost:4318`** (`agent/tracing.py`),
  which resolves to the Jaeger container on a dev machine but to nothing
  inside Azure Container Apps. It fails silently in the background
  (`BatchSpanProcessor`, by design — never breaks a request) and the
  file-based `ConsoleSpanExporter` still captures every span inside the
  container's ephemeral filesystem. Wiring a real OTLP collector endpoint in
  Azure (e.g., Azure Monitor's OTLP ingestion, or a managed Grafana/Jaeger) is
  out of scope for this PoC's minimal cut.
- **No autoscaling beyond `min/max_replicas`.** `container_min_replicas = 0`
  means the app scales to zero when idle (cheapest for a demo) at the cost of
  a cold start on the next request.
