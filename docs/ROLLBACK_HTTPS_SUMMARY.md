# Frontend Proxy and HTTPS Configuration Notes

## Architecture Decision: Express Proxy Server

The frontend uses an Express proxy server (`frontend/parking-manager/server.js`) rather than serving the React build directly. This approach:

- Routes all `/api/*` requests to the appropriate backend service
- Handles self-signed certificates on Madrid and Paris VMs by disabling TLS verification within the proxy (`NODE_TLS_REJECT_UNAUTHORIZED=0`) — this is intentional for this demo environment
- Serves the React static build on a single port (8080)
- Provides meaningful error responses (503, 504, 502) when backend services are unreachable

## Why Madrid and Paris Use HTTPS

The Madrid and Paris APIs run on private VMs within the Azure VNet and use self-signed TLS certificates. HTTPS is required to avoid mixed-content browser errors when the frontend App Service is served over HTTPS.

The proxy server handles certificate verification on behalf of the browser, so end users do not see certificate warnings.

## Backend URL Configuration

Backend URLs are configured via environment variables in the App Service (or `.env` file locally):

```
REACT_APP_LISBON_API_URL=<lisbon-container-app-url>
REACT_APP_MADRID_API_URL=https://<madrid-vm-ip>:3002
REACT_APP_PARIS_API_URL=https://<paris-vm-ip>:3003
REACT_APP_BERLIN_API_URL=<berlin-container-app-url>
REACT_APP_CHAOS_CONTROL_URL=<chaos-control-url>
REACT_APP_VM_HEALTH_CONTROL_URL=<vm-health-control-url>
```

See [HTTPS_SETUP_GUIDE.md](HTTPS_SETUP_GUIDE.md) for certificate generation on the VMs.
> **Historical note:** The portable deployment no longer disables TLS verification and uses private HTTP VM endpoints through App Service VNet integration.
