# Madrid API Deployment

Madrid runs on the private Windows VM created by Bicep. The GitHub workflow uses `windows-latest`, uploads an artifact to deployment storage, and calls Azure VM Run Command.

No self-hosted runner, public VM address, Bastion session, or GitHub private network is required.

## Required repository configuration

- OIDC variables from [Clean Subscription Deployment Bootstrap](DEPLOYMENT_BOOTSTRAP.md)
- `AZURE_DEPLOYMENTS_ENABLED=true`
- `MADRID_RESOURCE_GROUP`
- `MADRID_VM_NAME`
- `DEPLOYMENT_STORAGE_ACCOUNT`
- `HUB_RESOURCE_GROUP`
- `CHAOS_CONTROL_URL`

The infrastructure deployment grants the GitHub principal data access to deployment storage. The VM downloads a short-lived SAS URL and needs no storage role.

Run `.github/workflows/deploy-madrid-api.yml` after infrastructure succeeds. The workflow installs Node.js and NSSM through VM Run Command, configures the Windows service, and leaves the API reachable only inside the VNet.
