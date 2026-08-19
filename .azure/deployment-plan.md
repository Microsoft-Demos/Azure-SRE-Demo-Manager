# Azure Deployment Plan

> **Status:** Ready for Target Validation

Generated: 2026-08-19T11:55:00+01:00

---

## 1. Project Overview

**Goal:** Make Azure SRE Demo Manager reproducible in any clean Azure subscription without relying on identities, addresses, resources, GitHub runners, or network configuration from the retiring subscription.

**Path:** Modify existing Azure application

**Approval:** The user explicitly requested the IaC portability pass and authorized required repository updates. No target subscription exists yet, so the design remains subscription-agnostic.

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | POC / demo |
| Scale | Small |
| Budget | Cost-optimized |
| Subscription | Any clean Azure subscription; confirm its ID before deployment |
| Location | Configurable; `swedencentral` remains the example default |
| Compliance | No workload-specific requirement identified; target policy assignments must be reviewed |
| Deployment constraint | Static validation only in this session; no deployment or ARM what-if |

### Policy Constraints

The target subscription is not yet available. Before deployment, inventory its Azure Policy assignments, allowed regions/SKUs, required tags, and public-network restrictions. The current subscription has Defender-created policy assignments only and is used solely as a quota baseline.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Parking Manager | Frontend/proxy | React + Node.js/Express | `frontend/parking-manager` |
| Lisbon API | Container API | Node.js/Express | `backend/lisbon-parking-api` |
| Berlin API | Container API | Node.js/Express | `backend/berlin-parking-api` |
| Chaos Control | Container API | Node.js/Express | `backend/chaos-control` |
| VM Health Control | Container API | Node.js/Express + Azure Monitor ingestion | `backend/vm-health-control` |
| Berlin MCP | Container API | Python/FastMCP/FastAPI | `backend/berlin-mcp-server` |
| Madrid API | VM-hosted API | Node.js on Windows | `backend/madrid-parking-api` |
| Paris API | VM-hosted API | Node.js on Ubuntu | `backend/paris-parking-api` |

### Existing Infrastructure

| Item | Status |
|------|--------|
| Bicep | Subscription-scope orchestration in `infrastructure/` |
| GitHub Actions | Eleven Azure workflows with separate infrastructure and application gates |
| Dockerfiles | Lisbon, Berlin, Chaos Control, VM Health Control, Berlin MCP |
| AZD | Not configured |
| Terraform | Not used |

---

## 4. Recipe Selection

**Selected:** Bicep + Azure CLI + GitHub Actions

**Rationale:**

- The repository already uses subscription-scope modular Bicep.
- Existing workflows perform application packaging and VM Run Command deployment.
- Converting to AZD would be a broader deployment-system migration rather than a portability fix.
- Direct Bicep preserves the current operational model while removing subscription-specific dependencies.

---

## 5. Architecture

**Stack:** Container Apps + App Service + two demonstration VMs

### Service Mapping

| Component | Azure Service | SKU/profile |
|-----------|---------------|-------------|
| Frontend | Linux App Service | B1, Node 20 |
| Lisbon API | Azure Container Apps | Consumption workload profile |
| Berlin API | Azure Container Apps | Consumption workload profile |
| Chaos Control | Azure Container Apps | Consumption workload profile |
| VM Health Control | Azure Container Apps | Consumption workload profile |
| Berlin MCP | Azure Container Apps | Consumption workload profile |
| Madrid API | Windows VM | Standard_B2s |
| Paris API | Ubuntu VM | Standard_B2s |
| Images | Azure Container Registry | Basic |
| Deployment artifacts | StorageV2 | Standard_LRS |

### Networking

- One VNet (`10.0.0.0/16` by default).
- One VM subnet with explicit NAT Gateway outbound.
- One exclusive `/27` subnet for each Container Apps environment: Lisbon, Berlin, Chaos, and optional Berlin MCP.
- One delegated App Service integration subnet.
- One dedicated private-endpoint subnet for deployment storage.
- No GitHub-hosted runner VNet integration or custom GitHub runner subnet.
- Standard GitHub-hosted runners upload artifacts over the storage public endpoint and deploy to VMs through Azure VM Run Command.
- App Service integrates with the VNet to reach private Madrid and Paris APIs.

### Identity and RBAC

- GitHub Actions uses separate infrastructure and application workload identities (OIDC), not stored client secrets.
- Infrastructure and application operations use separate fail-closed GitHub variables.
- The infrastructure identity requires Contributor plus Role Based Access Control Administrator (or Owner) because Bicep creates role assignments.
- The application identity receives Contributor only on repository resource groups plus scoped ACR and storage data-plane roles.
- Container Apps managed identities receive AcrPull at the ACR resource scope.
- Madrid and Paris use short-lived SAS URLs for deployment artifacts; their managed identities receive no unused storage role.
- VM Health Control receives Monitoring Metrics Publisher at the DCR scope.
- The GitHub principal receives Storage Blob Data Contributor at the deployment storage account scope.

---

## 6. Provisioning Limit Checklist

The current Sweden Central subscription is a read-only quota baseline, not the deployment target. A future target must repeat these checks because quota and policy are subscription-specific.

| Resource Type | Number to Deploy | Baseline Total After Deployment | Baseline Limit/Quota | Notes |
|---------------|------------------|---------------------------------|----------------------|-------|
| Microsoft.Compute/virtualMachines (Standard_B2s / Standard BS Family) | 2 VMs / 4 vCPUs | 8 vCPUs | 100 vCPUs | `az quota`: current usage 4 |
| Microsoft.Compute regional cores | 4 vCPUs | 8 vCPUs | 100 vCPUs | `az quota`: current usage 4 |
| Microsoft.App/managedEnvironments | 4 | 8 | 50 | `az quota`: current usage 4 |
| Microsoft.Storage/storageAccounts | 1 | 3 | 250 | `az quota`: current usage 2 |
| Microsoft.Network/virtualNetworks | 1 | 3 | 1000 | `az quota`: current usage 2 |
| Microsoft.Network/subnets | 7 in one VNet | 7 | 3000 per VNet | Dedicated Container Apps, VM, App Service, private endpoint |
| Microsoft.Network/networkSecurityGroups | 2 | 13 | 5000 | `az quota`: current usage 11 |
| Microsoft.Network/networkInterfaces | 3 including private endpoint NIC | 6 | 65536 | `az quota`: current usage 3 |
| Microsoft.Network/privateEndpoints | 1 | 2 | 65536 | `az quota`: current usage 1 |
| Microsoft.Network/publicIPAddresses (Standard IPv4) | 1 | 3 | 1000 | NAT Gateway only; `az quota` current usage 2 |
| Microsoft.ContainerRegistry/registries | 1 | Target-specific | 100 per subscription | Official service limit; validate target policy |
| Microsoft.Web/serverfarms | 1 | Target-specific | 100 per resource group | One B1 plan |
| Microsoft.Resources/resourceGroups | 8 | Target-specific | 980 per subscription | Fixed Azure Resource Manager limit |

**Status:** Baseline capacity is sufficient. Target-subscription quota and policy validation remains mandatory before deployment.

---

## 7. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace
- [x] Gather requirements from repository and user objective
- [x] Select subscription-agnostic target and configurable location
- [x] Prepare resource inventory
- [x] Fetch quota baseline with Azure Quota CLI
- [x] Scan codebase
- [x] Select Bicep recipe
- [x] Plan architecture
- [x] User authorized the portability pass

### Phase 2: Execution

- [x] Replace shared Container Apps subnet with exclusive subnets
- [x] Add explicit VM outbound and a private-endpoint subnet
- [x] Integrate App Service with the VNet
- [x] Remove GitHub private-runner networking from new deployments
- [x] Move VM workflows to standard GitHub-hosted runners
- [x] Add a repeatable VM Health Control image workflow
- [x] Convert Azure login workflows to OIDC
- [x] Correct RBAC names, scopes, and prerequisites
- [x] Make full-demo optional components explicit in parameters
- [x] Update bootstrap and deployment documentation
- [x] Set status to `Ready for Validation`

### Phase 3: Validation

- [x] Invoke `azure-validate`
- [x] All static validation checks pass
  - [x] Build all Bicep templates
  - [x] Run Bicep linter on the subscription template
  - [x] Parse GitHub Actions YAML
  - [x] Build/test affected Node.js and Python components
  - [x] Review every role assignment statically
  - [x] Confirm no retired-subscription identifiers remain
  - [x] Confirm workflows are OIDC-only and use hosted runners
  - [x] Confirm target-dependent ARM validation remains a documented bootstrap gate
- [x] Record validation proof
- [ ] Confirm the future target subscription, policies, quota, and region
- [ ] Run target ARM validation and trusted manual what-if

### Phase 4: Deployment

- [ ] Not requested in this session

---

## 8. Validation Proof

| Check | Command Run | Result | Timestamp |
|-------|-------------|--------|-----------|
| Bicep compile and lint | `az bicep build` for main and changed modules; `az bicep lint --file infrastructure/main.bicep` | Pass, no diagnostics | 2026-08-19 |
| Generated ARM contract | Python assertions against `infrastructure/main.json` | Pass: dedicated subnets, VNet integration, NAT, secret refs, RBAC, no GitHub network settings | 2026-08-19 |
| Workflow security | YAML parser and assertions for hosted runners, OIDC v2, permissions, and separate gates | Pass: 11 authenticated jobs; PR compile has no Azure identity | 2026-08-19 |
| Frontend production build | `npm run build --prefix frontend/parking-manager` | Pass | 2026-08-19 |
| Frontend tests | `npm test --prefix frontend/parking-manager -- --watchAll=false --runInBand` | Pass: 1 suite, 1 test | 2026-08-19 |
| Code/script syntax | Node `--check`, Python compile, PowerShell parser, `bash -n` | Pass | 2026-08-19 |
| RBAC verification | Static scope/principal review plus Azure built-in role ID lookup | Pass: separate identities; RG Contributor, AcrPull, AcrPush, Blob Data Contributor, Monitoring Metrics Publisher | 2026-08-19 |
| Retired references | Repository search for old subscription and live resource identifiers | Pass: no matches | 2026-08-19 |

**Static validation performed by:** azure-validate workflow

**Not run:** ARM validate, cloud what-if, or deployment. These require the future target subscription and remain mandatory gates in `docs/DEPLOYMENT_BOOTSTRAP.md`.

---

## 9. Files to Generate or Modify

| File | Purpose | Status |
|------|---------|--------|
| `.azure/deployment-plan.md` | Deployment source of truth | Complete |
| `infrastructure/main.bicep` | Portable orchestration | Complete |
| `infrastructure/modules/hub.bicep` | Portable network topology | Complete |
| `infrastructure/modules/frontend.bicep` | App Service VNet integration | Complete |
| `infrastructure/modules/*-role-assignment.bicep` | Collision-free least-privilege RBAC | Complete |
| `.github/workflows/*.yml` | OIDC and hosted-runner bootstrap | Complete |
| `infrastructure/main.parameters.example.json` | Full-demo non-secret defaults | Complete |
| `docs/DEPLOYMENT_BOOTSTRAP.md` | Clean-subscription bootstrap | Complete |

---

## 10. Next Steps

> Current: Statically validated for theoretical clean-subscription replication

1. Reassess the retiring subscription independently of repository portability.
2. Before a future deployment, confirm target subscription, policies, quota, and region.
3. Run trusted ARM validation and manual what-if in that future target.
