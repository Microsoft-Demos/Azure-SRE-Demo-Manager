# Infrastructure Quick Reference

## Prepare a clean subscription

Follow [Clean Subscription Deployment Bootstrap](../docs/DEPLOYMENT_BOOTSTRAP.md):

1. Check target policy and quota.
2. Register providers.
3. Create the GitHub OIDC identity.
4. Grant Contributor and Role Based Access Control Administrator.
5. Configure GitHub variables and secrets.
6. Deploy infrastructure.
7. Map outputs and enable application workflows.

## Build Bicep locally

```powershell
az bicep build --file infrastructure/main.bicep
```

## Direct deployment

```powershell
az deployment sub create `
  --location swedencentral `
  --template-file infrastructure/main.bicep `
  --parameters infrastructure/main.parameters.example.json `
  --parameters adminPassword='<secure-vm-password>' `
  --parameters mcpAuthToken='<secure-mcp-token>' `
  --parameters applicationPrincipalId='<application-service-principal-object-id>'
```

## Outputs

```powershell
az deployment sub show `
  --name '<deployment-name>' `
  --query properties.outputs
```

## Retirement

```powershell
pwsh scripts/retire-azure-subscription.ps1 `
  -SubscriptionId '<subscription-id>' `
  -Action Assess
```

Deleting a subscription deployment record does not delete its resources.
