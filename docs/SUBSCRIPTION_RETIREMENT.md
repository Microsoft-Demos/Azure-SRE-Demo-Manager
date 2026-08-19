# Azure Subscription Retirement

Use this runbook to retire an Azure deployment without running an application test, deployment validation, or ARM what-if. The retirement script uses control-plane reads only until an explicit destructive action is selected.

## Safety model

- Infrastructure and application workflows use separate repository-level fail-closed gates.
- `Assess` is read-only.
- `RemoveRepositoryResources` deletes only the known `rg-parking-*` resource groups for the selected environment.
- Unrecognized resource groups are never deleted by the script.
- GitHub-hosted runner networking must be detached in GitHub before its Azure network settings resource is removed.
- `CancelSubscription` refuses to run while any resource, resource group, lock, or custom-role dependency remains.
- Cancellation also requires the exact subscription ID twice, an external-context attestation, and an unconditioned Azure Owner role.

## Prerequisites

- PowerShell 7 or later
- Azure CLI with access to the target subscription
- The Azure CLI `account` extension for the final cancellation command:

  ```powershell
  az extension add --name account
  ```

- GitHub organization administration for hosted-compute networking
- GitHub repository administration for Actions secrets, variables, workflows, and self-hosted runners

## 1. Freeze deployment automation

Set repository-level `AZURE_INFRA_DEPLOYMENTS_ENABLED=false` and `AZURE_DEPLOYMENTS_ENABLED=false`; do not rely on either variable being absent because organization-level values can be inherited. Disable the Azure workflows in GitHub while retirement is in progress.

```powershell
gh variable set AZURE_DEPLOYMENTS_ENABLED --repo '<owner>/<repository>' --body false
gh variable set AZURE_INFRA_DEPLOYMENTS_ENABLED --repo '<owner>/<repository>' --body false
```

Remove these repository secrets after confirming no remaining cleanup job needs them:

- `AZURE_CREDENTIALS`
- `AZURE_VM_ADMIN_PASSWORD`
- `MCP_AUTH_TOKEN`

Remove Azure resource names, URLs, resource IDs, and subscription IDs from repository Actions variables. Remove the Madrid and Paris self-hosted runner registrations after their VMs no longer need to run jobs.

## 2. Run the read-only assessment

```powershell
pwsh ./scripts/retire-azure-subscription.ps1 `
  -SubscriptionId '<subscription-id>' `
  -Action Assess `
  -ReportPath './retirement-assessment.json'
```

The report distinguishes known repository groups from unexpected groups and lists Recovery Services vaults, GitHub network settings, budgets, policies, locks, and custom roles. `readyForCancellation` must be `true` before cancellation.

## 3. Resolve data and non-repository resources

For every unexpected resource group, identify its owner and choose one action:

1. Back up and move the resource to another subscription.
2. Obtain the owner's explicit approval and delete it.
3. Stop retirement.

Recovery Services vaults require a separate data-retention decision. Verify protected items, export any required data, stop protection according to the chosen retention policy, and remove soft-deleted backup items before deleting the vault.

Do not treat stale Azure Resource Graph entries as live resources. Confirm with `az group show` and `az resource list`.

## 4. Detach GitHub networking

An organization owner with the `read:network_configurations` and `write:network_configurations` permissions must remove the hosted-compute network configuration that references the Azure subnet.

Also remove any larger-runner groups or runner registrations that use that network. Confirm the GitHub configuration is gone before proceeding.

## 5. Remove repository-owned Azure resources

The following command first removes the Azure `GitHub.Network/networkSettings` resource, then deletes only the repository resource groups. It will prompt before each destructive operation.

```powershell
pwsh ./scripts/retire-azure-subscription.ps1 `
  -SubscriptionId '<subscription-id>' `
  -ConfirmSubscriptionId '<subscription-id>' `
  -Environment dev `
  -Action RemoveRepositoryResources `
  -GitHubNetworkConfigurationRemoved
```

The script waits for each requested resource-group deletion and prints a fresh assessment. It does not delete unexpected groups.

## 6. Remove external identity context

For each dedicated Entra application or service principal:

1. List all role assignments across accessible subscriptions.
2. Confirm it is not used by another repository, subscription, tenant application, or automation.
3. Remove credentials and federated identity credentials.
4. Delete the application/service principal only when it is confirmed to be dedicated.

Direct subscription role assignments disappear with the subscription, but Entra applications and their credentials do not.

The removed `infrastructure/main.parameters.json` contained a non-placeholder VM password. Treat it as compromised because it remains in Git history. Do not reuse it. Rotate it if either VM will remain active; otherwise deletion of the VMs invalidates it.

## 7. Reassess and cancel

Run `Assess` again. Resolve every remaining resource group, resource, lock, and custom-role dependency. Microsoft recommends deleting all resources and groups before cancellation.

In Cost Management + Billing, separately check for and cancel any Azure Support plan that is no longer needed. Also cancel Marketplace SaaS subscriptions and review reservations or other billing-scope purchases; subscription cancellation does not necessarily cancel those products.

After GitHub and Entra cleanup is complete, authenticate as an unconditioned subscription Owner and run:

```powershell
pwsh ./scripts/retire-azure-subscription.ps1 `
  -SubscriptionId '<subscription-id>' `
  -ConfirmSubscriptionId '<subscription-id>' `
  -Action CancelSubscription `
  -ExternalContextRemoved
```

Cancellation stops usage billing for resources in the subscription, but Azure retains data temporarily and issues a final bill after the billing cycle closes. Separately billed support, SaaS, reservation, and billing-scope products must be handled independently. The Azure account itself is not deleted automatically.
