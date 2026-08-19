# Paris API Deployment Automation

`.github/workflows/deploy-paris-api.yml` packages the Paris API on a standard `ubuntu-latest` runner, uploads it to Azure deployment storage, and invokes the private VM through Azure VM Run Command.

The workflow:

1. Authenticates with Azure OIDC.
2. Uploads a short-lived deployment artifact.
3. Invokes the Linux VM through the Azure control plane.
4. Installs dependencies and configures the systemd service.
5. Removes the deployment artifact.

It requires the common OIDC variables plus `PARIS_VM_NAME`, `PARIS_RESOURCE_GROUP`, `DEPLOYMENT_STORAGE_ACCOUNT`, `HUB_RESOURCE_GROUP`, and `CHAOS_CONTROL_URL`.

See [Clean Subscription Deployment Bootstrap](DEPLOYMENT_BOOTSTRAP.md).
