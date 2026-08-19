# GitHub Actions Azure Deployment

Azure workflows are fail-closed. Infrastructure jobs require `AZURE_INFRA_DEPLOYMENTS_ENABLED=true`; application jobs require `AZURE_DEPLOYMENTS_ENABLED=true`.

The workflows authenticate with GitHub OpenID Connect (OIDC). No Azure client secret or `AZURE_CREDENTIALS` JSON is used.

## Workflows

| Workflow | Purpose | Runner |
|----------|---------|--------|
| `infra-whatif.yml` | PR compilation and trusted manual cloud what-if | `ubuntu-latest` |
| `infra-deploy.yml` | Manual subscription-scope infrastructure deployment | `ubuntu-latest` |
| `deploy-lisbon-api.yml` | Lisbon Container App image | `ubuntu-latest` |
| `deploy-berlin-api.yml` | Berlin Container App image | `ubuntu-latest` |
| `deploy-chaos-control.yml` | Chaos Control Container App image | `ubuntu-latest` |
| `deploy-vm-health-control.yml` | VM Health Control Container App image | `ubuntu-latest` |
| `deploy-berlin-mcp.yml` | Berlin MCP Container App image and token | `ubuntu-latest` |
| `deploy-frontend.yml` | React/Express App Service package | `ubuntu-latest` |
| `deploy-madrid-api.yml` | Windows VM package through Azure VM Run Command | `windows-latest` |
| `deploy-paris-api.yml` | Linux VM package through Azure VM Run Command | `ubuntu-latest` |
| `deploy-lisbon-chaos-alerts.yml` | Lisbon scheduled-query alert rules | `ubuntu-latest` |

Madrid and Paris do not require self-hosted runners or GitHub private networking. Hosted runners upload a short-lived package to deployment storage and invoke the VM through the Azure control plane.

## Authentication

Every Azure job requires these repository variables:

| Variable | Meaning |
|----------|---------|
| `AZURE_INFRA_CLIENT_ID` | Infrastructure OIDC client ID; subscription Contributor + RBAC Administrator |
| `AZURE_APP_CLIENT_ID` | Application OIDC client ID; resource-group/resource-scoped roles only |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| `AZURE_APP_PRINCIPAL_OBJECT_ID` | Application service principal object ID, used by Bicep RBAC assignments |
| `AZURE_INFRA_DEPLOYMENTS_ENABLED` | Enables infrastructure deployment and manual cloud what-if |
| `AZURE_DEPLOYMENTS_ENABLED` | Enables application deployments after output mapping |

Only the infrastructure principal needs **Contributor** and **Role Based Access Control Administrator** at subscription scope. Bicep grants the application principal Contributor on repository resource groups plus narrowly scoped data-plane roles.

Required secrets:

| Secret | Used by |
|--------|---------|
| `AZURE_VM_ADMIN_PASSWORD` | Infrastructure deployment |
| `MCP_AUTH_TOKEN` | Infrastructure and Berlin MCP deployment |

See [Clean Subscription Deployment Bootstrap](../../docs/DEPLOYMENT_BOOTSTRAP.md) for OIDC federation, provider registration, variables, output mapping, and deployment order.

## Infrastructure parameters

`infrastructure/main.parameters.example.json` contains only non-secret, portable defaults. The full demo enables both VMs and Berlin MCP. Secrets are supplied separately by the workflow.

Local operators can copy it to the ignored `infrastructure/main.parameters.json`:

```powershell
Copy-Item infrastructure/main.parameters.example.json infrastructure/main.parameters.json
```

## Deployment order

1. Keep both deployment gates `false`.
2. Configure OIDC, roles, providers, secrets, and core Azure variables.
3. Enable the infrastructure workflows and set `AZURE_INFRA_DEPLOYMENTS_ENABLED=true`.
4. Run `infra-deploy.yml`, then return the infrastructure gate to `false`.
5. Map deployment outputs to the application variables listed in the bootstrap guide.
6. Enable application workflows and set `AZURE_DEPLOYMENTS_ENABLED=true`.
7. Run application workflows.
8. Run the frontend workflow after all API URLs are configured.

Do not reuse variables or credentials from another subscription.
