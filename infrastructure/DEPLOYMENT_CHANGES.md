# Infrastructure Portability Changes

The current templates are designed for clean-subscription reproduction:

- Dedicated `/27` subnet per Container Apps environment
- App Service VNet integration for private VM APIs
- Explicit VM NAT outbound
- Dedicated private-endpoint subnet
- Standard GitHub-hosted runners with Azure VM Run Command
- GitHub OIDC instead of client-secret credentials
- Collision-free, resource-scoped ACR and storage role assignments
- ACR admin account disabled
- Conditional VM NICs and public IPs
- Full-demo non-secret example parameters

Legacy GitHub private-runner networking was removed from new deployments. The retirement script still recognizes old `GitHub.Network/networkSettings` resources so existing subscriptions can be cleaned safely.
