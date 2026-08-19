# Clean Subscription Deployment Bootstrap

This guide creates the deployment context required to reproduce Azure SRE Demo Manager in a clean Azure subscription. It does not reuse identities, networking, addresses, or credentials from another subscription.

## Prerequisites

- Azure CLI and PowerShell 7
- GitHub CLI authenticated with repository administration access
- Permission to create an Entra application and service principal
- Permission to grant Contributor and Role Based Access Control Administrator on the target subscription
- A target region that passes policy, SKU availability, and quota checks

Set local values:

```powershell
$SubscriptionId = '<target-subscription-id>'
$Location = 'swedencentral'
$Repository = '<owner>/<repository>'
$InfraApplicationName = 'github-azure-sre-demo-manager-infra'
$AppApplicationName = 'github-azure-sre-demo-manager-app'

az account set --subscription $SubscriptionId
```

## 1. Validate target policy and quota

Install the quota extension and register its provider:

```powershell
az extension add --name quota --upgrade --yes
az provider register `
  --namespace Microsoft.Quota `
  --subscription $SubscriptionId `
  --wait
```

Review target-subscription policy assignments before selecting a region:

```powershell
az policy assignment list `
  --scope "/subscriptions/$SubscriptionId" `
  --disable-scope-strict-match `
  --output table
```

Also review effective exemptions:

```powershell
az policy exemption list `
  --scope "/subscriptions/$SubscriptionId" `
  --disable-scope-strict-match `
  --output table
```

At minimum, verify:

- 4 Container Apps managed environments
- 4 Standard BS-family vCPUs for two `Standard_B2s` VMs
- 1 Standard public IP for VM NAT
- 1 VNet, 7 subnets, 2 NSGs, and 1 private endpoint
- 1 storage account, 1 Basic ACR, and 1 B1 Linux App Service plan

Use `az quota list` and `az quota usage list` for `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.App`, and `Microsoft.Storage` in the selected region.

## 2. Register resource providers

```powershell
$Providers = @(
  'Microsoft.App'
  'Microsoft.Authorization'
  'Microsoft.Compute'
  'Microsoft.ContainerRegistry'
  'Microsoft.Insights'
  'Microsoft.ManagedIdentity'
  'Microsoft.Network'
  'Microsoft.OperationalInsights'
  'Microsoft.Quota'
  'Microsoft.Resources'
  'Microsoft.Storage'
  'Microsoft.Web'
)

foreach ($Provider in $Providers) {
  az provider register `
    --namespace $Provider `
    --subscription $SubscriptionId `
    --wait
}
```

## 3. Create separate OIDC identities

The infrastructure identity provisions resources and role assignments. The application identity receives only resource-group Contributor plus the ACR and storage data-plane roles assigned by Bicep.

```powershell
$InfraClientId = az ad app create `
  --display-name $InfraApplicationName `
  --query appId `
  --output tsv

$InfraPrincipalObjectId = az ad sp create `
  --id $InfraClientId `
  --query id `
  --output tsv

$AppClientId = az ad app create `
  --display-name $AppApplicationName `
  --query appId `
  --output tsv

$AppPrincipalObjectId = az ad sp create `
  --id $AppClientId `
  --query id `
  --output tsv

$Scope = "/subscriptions/$SubscriptionId"

az role assignment create `
  --assignee-object-id $InfraPrincipalObjectId `
  --assignee-principal-type ServicePrincipal `
  --role Contributor `
  --scope $Scope

az role assignment create `
  --assignee-object-id $InfraPrincipalObjectId `
  --assignee-principal-type ServicePrincipal `
  --role 'Role Based Access Control Administrator' `
  --scope $Scope
```

Do not grant subscription-level Contributor or RBAC administration to the application identity. Bicep grants it Contributor only on the eight application resource groups, plus AcrPush and Storage Blob Data Contributor at resource scope.

## 4. Add GitHub federated credentials

Create credentials for the main branch and each GitHub environment used by `infra-deploy.yml`. Pull requests compile Bicep without Azure authentication; cloud what-if is manual from `main`.

```powershell
$Issuer = 'https://token.actions.githubusercontent.com'
$Audience = @('api://AzureADTokenExchange')

$InfraSubjects = @{
  'main-branch' = "repo:$($Repository):ref:refs/heads/main"
  'environment-dev' = "repo:$($Repository):environment:dev"
  'environment-test' = "repo:$($Repository):environment:test"
  'environment-prod' = "repo:$($Repository):environment:prod"
}

foreach ($Entry in $InfraSubjects.GetEnumerator()) {
  $Credential = @{
    name = "infra-$($Entry.Key)"
    issuer = $Issuer
    subject = $Entry.Value
    audiences = $Audience
  } | ConvertTo-Json

  $File = New-TemporaryFile
  Set-Content -LiteralPath $File -Value $Credential -Encoding utf8NoBOM
  az ad app federated-credential create `
    --id $InfraClientId `
    --parameters $File
  Remove-Item -LiteralPath $File
}

$AppCredential = @{
  name = 'app-main-branch'
  issuer = $Issuer
  subject = "repo:$($Repository):ref:refs/heads/main"
  audiences = $Audience
} | ConvertTo-Json

$File = New-TemporaryFile
Set-Content -LiteralPath $File -Value $AppCredential -Encoding utf8NoBOM
az ad app federated-credential create `
  --id $AppClientId `
  --parameters $File
Remove-Item -LiteralPath $File
```

If the repository uses different branch or environment names, create matching subjects instead.

## 5. Configure GitHub

Keep deployments locked while configuration is incomplete:

```powershell
$TenantId = az account show --query tenantId --output tsv

gh variable set AZURE_INFRA_CLIENT_ID --repo $Repository --body $InfraClientId
gh variable set AZURE_APP_CLIENT_ID --repo $Repository --body $AppClientId
gh variable set AZURE_TENANT_ID --repo $Repository --body $TenantId
gh variable set AZURE_SUBSCRIPTION_ID --repo $Repository --body $SubscriptionId
gh variable set AZURE_APP_PRINCIPAL_OBJECT_ID --repo $Repository --body $AppPrincipalObjectId
gh variable set AZURE_INFRA_DEPLOYMENTS_ENABLED --repo $Repository --body false
gh variable set AZURE_DEPLOYMENTS_ENABLED --repo $Repository --body false

gh secret set AZURE_VM_ADMIN_PASSWORD --repo $Repository
gh secret set MCP_AUTH_TOKEN --repo $Repository
```

The VM password must satisfy Azure VM complexity rules. Use a random MCP token of at least 32 bytes.

Enable only the infrastructure workflows first:

```powershell
$InfrastructureWorkflows = @(
  'infra-whatif.yml'
  'infra-deploy.yml'
)

foreach ($Workflow in $InfrastructureWorkflows) {
  gh workflow enable $Workflow --repo $Repository
}
```

Application workflows remain disabled and locked:

```powershell
$ApplicationWorkflows = @(
  'deploy-lisbon-api.yml'
  'deploy-berlin-api.yml'
  'deploy-chaos-control.yml'
  'deploy-vm-health-control.yml'
  'deploy-berlin-mcp.yml'
  'deploy-madrid-api.yml'
  'deploy-paris-api.yml'
  'deploy-frontend.yml'
  'deploy-lisbon-chaos-alerts.yml'
)
```

## 6. Deploy infrastructure

Enable infrastructure operations:

```powershell
gh variable set AZURE_INFRA_DEPLOYMENTS_ENABLED `
  --repo $Repository `
  --body true
```

Run `Deploy Infrastructure to Azure` manually with:

- Environment: `dev`
- Location: the validated target region
- Parameters: `infrastructure/main.parameters.example.json`
- Confirmation: `DEPLOY`

The example deploys the full demo: Madrid, Paris, Berlin MCP, ACR, deployment storage, monitoring, and frontend infrastructure.

After it succeeds, freeze infrastructure changes again:

```powershell
gh variable set AZURE_INFRA_DEPLOYMENTS_ENABLED `
  --repo $Repository `
  --body false
```

## 7. Map outputs to application variables

Retrieve the successful deployment outputs and set:

| Repository variable | Bicep output |
|---------------------|--------------|
| `AZURE_CONTAINER_REGISTRY` | `containerRegistryName` |
| `AZURE_WEBAPP_NAME` | `frontendAppServiceName` |
| `APP_SERVICE_SUBNET_PREFIX` | `appServiceSubnetPrefix` |
| `FRONTEND_RESOURCE_GROUP` | `frontendResourceGroup` |
| `HUB_RESOURCE_GROUP` | `hubResourceGroup` |
| `LISBON_RESOURCE_GROUP` | `lisbonResourceGroup` |
| `BERLIN_RESOURCE_GROUP` | `berlinResourceGroup` |
| `BERLIN_MCP_RESOURCE_GROUP` | `berlinMcpResourceGroup` |
| `CHAOS_CONTROL_RESOURCE_GROUP` | `chaosControlResourceGroup` |
| `CHAOS_CONTROL_CONTAINER_APP_NAME` | `chaosControlContainerAppName` |
| `VM_HEALTH_CONTROL_CONTAINER_APP_NAME` | `vmHealthControlContainerAppName` |
| `MADRID_RESOURCE_GROUP` | `madridResourceGroup` |
| `MADRID_VM_NAME` | `madridVmName` |
| `PARIS_RESOURCE_GROUP` | `parisResourceGroup` |
| `PARIS_VM_NAME` | `parisVmName` |
| `DEPLOYMENT_STORAGE_ACCOUNT` | `deploymentStorageAccountName` |
| `LISBON_API_URL` | `lisbonApiUrl` |
| `BERLIN_API_URL` | `berlinApiUrl` |
| `MADRID_API_URL` | `madridApiUrl` |
| `PARIS_API_URL` | `parisApiUrl` |
| `CHAOS_CONTROL_URL` | `chaosControlUrl` |
| `VM_HEALTH_CONTROL_URL` | `vmHealthControlUrl` |
| `LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` | `logAnalyticsWorkspaceId` |

`ACTION_GROUP_RESOURCE_ID` is optional for Lisbon chaos alerts.

## 8. Enable application deployment

After every value points to the new subscription:

```powershell
foreach ($Workflow in $ApplicationWorkflows) {
  gh workflow enable $Workflow --repo $Repository
}

gh variable set AZURE_DEPLOYMENTS_ENABLED `
  --repo $Repository `
  --body true
```

Deploy Lisbon, Berlin, Chaos Control, VM Health Control, Berlin MCP, Madrid, and Paris before the frontend. VM workflows use standard hosted runners and Azure VM Run Command; no runner installation or GitHub private network is required.

## Reproducibility boundary

Bicep reproduces Azure infrastructure. GitHub OIDC federation, GitHub secrets/variables, Entra application ownership, target policy/quota approval, and application workflow execution are explicit bootstrap steps because they exist outside an Azure subscription deployment.
