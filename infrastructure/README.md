# Azure Infrastructure

The Bicep templates deploy Azure SRE Demo Manager at subscription scope. They are subscription-agnostic: globally unique names derive from target resource-group IDs, secrets are supplied separately, and no GitHub or Entra resource from another subscription is referenced.

Start with [Clean Subscription Deployment Bootstrap](../docs/DEPLOYMENT_BOOTSTRAP.md).

## Resource groups

| Resource group | Main resources |
|----------------|----------------|
| `rg-parking-hub-{env}` | VNet, NAT Gateway, Log Analytics, ACR, deployment storage, private endpoint, monitoring rules |
| `rg-parking-frontend-{env}` | Linux B1 App Service plan, frontend App Service, Application Insights |
| `rg-parking-lisbon-{env}` | Lisbon Container Apps environment and app |
| `rg-parking-berlin-{env}` | Berlin Container Apps environment and app |
| `rg-parking-chaos-{env}` | Chaos and VM Health Container Apps |
| `rg-parking-madrid-{env}` | Windows `Standard_B2s` VM |
| `rg-parking-paris-{env}` | Ubuntu `Standard_B2s` VM |
| `rg-parking-berlin-mcp-{env}` | Optional Berlin MCP environment, app, Log Analytics, and Application Insights |

## Network topology

Default VNet: `10.0.0.0/16`

| Subnet | Default prefix | Purpose |
|--------|----------------|---------|
| `snet-vms` | `10.0.1.0/24` | Madrid and Paris; explicit NAT outbound |
| `snet-container-lisbon` | `10.0.2.0/27` | Exclusive Lisbon Container Apps environment |
| `snet-container-berlin` | `10.0.2.32/27` | Exclusive Berlin Container Apps environment |
| `snet-container-chaos` | `10.0.2.64/27` | Exclusive Chaos Container Apps environment |
| `snet-container-berlin-mcp` | `10.0.2.96/27` | Exclusive Berlin MCP environment |
| `snet-app-service` | `10.0.5.0/24` | Regional App Service VNet integration |
| `snet-private-endpoints` | `10.0.6.0/27` | Deployment storage private endpoint |

Each Container Apps environment has its own delegated subnet, as required by Azure. App Service reaches the private VM APIs through VNet integration. Private VMs download deployment artifacts through explicit NAT and a storage private endpoint.

Standard GitHub-hosted runners use Azure OIDC, the public deployment-storage endpoint, and Azure VM Run Command. New deployments do not create `GitHub.Network/networkSettings`, private hosted-runner subnets, or self-hosted runner registrations.

## Required roles

The infrastructure provisioning identity needs:

- **Contributor** at the target subscription
- **Role Based Access Control Administrator** at the target subscription

Bicep creates resource-scoped AcrPull, AcrPush, Storage Blob Data Contributor, and Monitoring Metrics Publisher assignments. Contributor alone is insufficient because it cannot write role assignments.

The separate application identity receives Contributor only on this deployment's resource groups. It never receives subscription-level RBAC administration.

## Parameters

`main.parameters.example.json` is a full-demo, non-secret example. It enables Madrid, Paris, Berlin MCP, and ACR.

Secrets are separate:

- `adminPassword`
- `mcpAuthToken`

`deploy.sh` prompts for both when required. Set `APPLICATION_PRINCIPAL_ID` before running it if the resulting infrastructure will be deployed by GitHub Actions.

Important network parameters:

| Parameter | Default |
|-----------|---------|
| `vnetAddressPrefix` | `10.0.0.0/16` |
| `vmSubnetPrefix` | `10.0.1.0/24` |
| `lisbonContainerSubnetPrefix` | `10.0.2.0/27` |
| `berlinContainerSubnetPrefix` | `10.0.2.32/27` |
| `chaosContainerSubnetPrefix` | `10.0.2.64/27` |
| `berlinMcpContainerSubnetPrefix` | `10.0.2.96/27` |
| `appServiceSubnetPrefix` | `10.0.5.0/24` |
| `privateEndpointSubnetPrefix` | `10.0.6.0/27` |

## Local Bicep deployment

Copy the example to an ignored local file:

```powershell
Copy-Item main.parameters.example.json main.parameters.local.json
```

Deploy only after target policy, quota, providers, and roles have been checked:

```powershell
az deployment sub create `
  --location swedencentral `
  --template-file main.bicep `
  --parameters main.parameters.local.json `
  --parameters adminPassword='<secure-vm-password>' `
  --parameters mcpAuthToken='<secure-mcp-token>' `
  --parameters applicationPrincipalId='<application-service-principal-object-id>'
```

The preferred deployment path is the OIDC-enabled `infra-deploy.yml` workflow described in the bootstrap guide.

## Application deployment

Infrastructure initially uses public placeholder images so ACR and managed identities can be created without circular dependencies. Bicep grants:

- AcrPull to each Container App managed identity
- AcrPush to the GitHub deployment principal

Run application workflows after infrastructure output values have been mapped to repository variables. Run the frontend last.

## Cleanup

Do not delete deployment records or resource groups ad hoc. Use the read-only-first retirement workflow:

```powershell
pwsh ../scripts/retire-azure-subscription.ps1 `
  -SubscriptionId '<subscription-id>' `
  -Action Assess
```

See [Azure Subscription Retirement](../docs/SUBSCRIPTION_RETIREMENT.md).
