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
│   └── container-app/       # generic enough to deploy BOTH the API and the frontend
└── live/
    ├── root.hcl            # remote state backend + provider, inherited by everything below
    └── dev/
        ├── env.hcl         # the ONLY file with dev-specific values (region, sizing, tags)
        ├── resource-group/terragrunt.hcl
        ├── log-analytics/terragrunt.hcl
        ├── container-registry/terragrunt.hcl
        ├── container-app-environment/terragrunt.hcl
        ├── container-app/terragrunt.hcl        # backend (../api)
        └── frontend-app/terragrunt.hcl         # chat UI (../frontend)
```

`frontend-app` reuses the exact same `modules//container-app` as the backend --
only the inputs differ (image name, `container_name = "web"`, `target_port = 8080`
for nginx). Its `env_vars.API_URL` is wired straight from `container-app`'s own
`fqdn` output via a Terragrunt `dependency` block -- no URL is ever
copy-pasted between components, and the frontend Docker image never needs to
know the backend's address at build time (see
[../frontend/src/lib/config.ts](../frontend/src/lib/config.ts) and
[../frontend/docker-entrypoint.sh](../frontend/docker-entrypoint.sh): the
value is injected into `config.js` when the container *starts*, by nginx's
own `/docker-entrypoint.d/` mechanism).

Adding a `staging` or `prod` environment later means copying `live/dev/` to
`live/staging/`, editing `env.hcl`, and nothing else — no module changes, no
duplicated Terraform.

## What's actually deployed (and what isn't)

Matches the minimal scope cut ([domain/07-scope-cutlines.md](../domain/07-scope-cutlines.md)):
two Container Apps (the FastAPI backend and the React chat UI) sharing one
Container Apps Environment, one Azure Container Registry, and one Log
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

# 3. bring up the rest of the stack
# Terragrunt's get_env() (live/dev/container-app/terragrunt.hcl) reads process
# env vars, not .env files -- load .env into the shell first, same pattern
# used everywhere else in this repo (eval/run_eval.py, uvicorn locally):
set -a && source .env && set +a
cd infra/live/dev
terragrunt run --all apply
```

Note: `.env` never touches the repo or the container image, but Terraform
*does* record the secret values in its state file once applied (it needs them
to detect drift) -- for this PoC that's an accepted trade-off, same reasoning
as the no-Key-Vault gap in [domain/06-security.md](../domain/06-security.md).
Anyone with read access to the remote state storage account can read them in
plaintext; that stops being acceptable the moment this is more than a PoC.

`terragrunt run --all apply` resolves the dependency graph automatically
(resource group → log analytics + container registry → container app
environment → container app → frontend-app) via the `dependency` blocks in
each component's `terragrunt.hcl` — no manual ordering needed beyond pushing
both images before the container app that references each one first runs.
Build and push the frontend image the same way as step 2, just against
`../../../../frontend` instead of the repo root:

```bash
cd infra/live/dev/frontend-app
docker build -t "$ACR_LOGIN_SERVER/port-intelligence-frontend:latest" ../../../../frontend
docker push "$ACR_LOGIN_SERVER/port-intelligence-frontend:latest"
```

## Deploying via GitHub Actions

[.github/workflows/deploy.yml](../.github/workflows/deploy.yml) automates the exact manual sequence
above (it can't use `run --all apply` for the same reason a human can't: the image has to exist in
the registry before the container app references it). It runs after
[ci.yml](../.github/workflows/ci.yml) succeeds on `main`, or on demand (`workflow_dispatch`).

**Auth is OIDC, not a stored secret.** `azure/login` exchanges a GitHub-issued OIDC token for a
short-lived Azure token every run — there's no client secret sitting in GitHub at all. Setting up
that trust relationship, once, per subscription:

```bash
# 1. App registration + service principal
APP_ID=$(az ad app create --display-name "gh-actions-portintel-poc" --query appId -o tsv)
az ad sp create --id "$APP_ID"

# 2. Federated credential: trust GitHub OIDC tokens, but only for this repo's main branch.
#
# GOTCHA (hit for real on the first deploy run): the `subject` value here has
# to match EXACTLY what GitHub's OIDC token presents -- and that is not
# always the plain `repo:<owner>/<repo>:ref:refs/heads/<branch>` every guide
# shows. Some accounts/orgs get GitHub's immutable-ID subject format instead:
# `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>`. Guessing
# wrong fails with `AADSTS700213: No matching federated identity record
# found`, and the error conveniently echoes back the exact subject GitHub
# actually sent -- copy that string verbatim rather than assuming the simple
# form, or check it upfront by decoding a token from a debug run
# (https://github.com/octo-org/octo-repo/actions -> a run's OIDC step summary).
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "github-main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
# If step 1's federated credential doesn't match, fix it with:
#   az ad app federated-credential update --id "$APP_ID" \
#     --federated-credential-id github-main-branch --parameters '{...}'

# 3. Least-privilege role assignments -- scoped to the two resource groups
# this project actually touches, never the whole subscription.
SUB_ID="<subscription-id>"
az role assignment create --assignee "$APP_ID" --role Contributor \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-portintel-dev"
az role assignment create --assignee "$APP_ID" --role Contributor \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-tfstate-portintel"

# Contributor deliberately excludes managing role assignments -- but
# modules/container-app creates one (the AcrPull grant for its own managed
# identity). Grant that narrowly too, on the app's resource group only:
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-portintel-dev"
```

Then set the GitHub secrets (`gh secret set NAME --body "$VALUE" --repo <owner>/<repo>`):
`AZURE_CLIENT_ID` (the app's `appId`), `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, plus the same
`ANTHROPIC_API_KEY` / `ANTHROPIC_WORKSPACE_ID` / `API_KEY` already used locally.

`User Access Administrator` on a whole resource group is broader than the single role assignment
Terraform actually creates — a fully least-privilege setup would use a custom role scoped to just
`Microsoft.Authorization/roleAssignments/write` on the ACR. Documented here as a known trade-off
rather than silently over-granting, same spirit as the no-Key-Vault gap in
[domain/06-security.md](../domain/06-security.md).

## What's verified — applied to a real Azure subscription

This has been deployed for real, not just planned. Live URL and the real problems hit along the way
(region restrictions, an unregistered resource provider, an arm64/amd64 image mismatch, an orphaned
resource after a failed apply, and a stale-revision-hostname bug in this module's original `fqdn`
output) are in [domain/08-phases.md](../domain/08-phases.md#real-evidence-applied-to-a-real-azure-subscription) —
worth reading before assuming `terraform validate` passing means a real subscription will cooperate.

- Every module validates standalone (`terraform validate`) and applies cleanly end to end via
  Terragrunt (`resource-group` → `log-analytics` + `container-registry` → `container-app-environment`
  → `container-app`).
- The Docker image builds, runs, and was pushed to the real ACR — but only after rebuilding
  explicitly for `linux/amd64` (see the phases doc; a plain `docker build` on Apple Silicon produces
  an arm64-only manifest that Azure Container Apps rejects).
- `/health`, the authenticated `/sap/PortCallSet`, and `/query` (the real agent, calling the real
  Claude API) all responded `200` from the live Azure URL.
- The frontend Container App serves the chat UI and talks to the backend Container App over the
  public internet (both are `external_enabled = true` Container Apps, domain/06-security.md #4) —
  not over a private VNet. Acceptable for a PoC that's meant to be reachable with just a browser and
  an API key; a production version would put both behind a VNet-integrated environment.

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
- **A `:latest` image push doesn't force a new revision.** Both `deploy.yml` and the manual sequence
  above push to a mutable `:latest` tag; if nothing else in a `terragrunt.hcl` changed, `terraform
  apply` sees no diff and never asks Azure to roll a new revision, so the old code keeps running
  despite the new image sitting in ACR. Hit for real and worked around manually
  ([domain/08-phases.md](../domain/08-phases.md#real-evidence-applied-to-a-real-azure-subscription));
  not yet fixed in the pipeline itself. A digest- or commit-sha-based `revision_suffix` in each
  `container-app*/terragrunt.hcl` would close this properly.
