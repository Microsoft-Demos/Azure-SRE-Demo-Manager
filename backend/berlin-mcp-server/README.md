# Berlin MCP Monitoring Server

The Berlin MCP server exposes monitoring tools for the Berlin Parking API through MCP Streamable HTTP. It runs as an optional Azure Container App.

## Endpoints

| Endpoint | Purpose | Authentication |
|----------|---------|----------------|
| `GET /startup` | Container App startup probe | Public |
| `GET /health` | Health and readiness | Public |
| `GET /` | Service metadata | Public |
| `POST /mcp` | MCP JSON-RPC endpoint | Bearer token when configured |

## Environment variables

| Variable | Purpose |
|----------|---------|
| `BERLIN_API_URL` | Berlin Parking API base URL |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Application Insights logging |
| `MCP_AUTH_TOKEN` | MCP bearer token |

Local default:

```powershell
$env:BERLIN_API_URL = 'http://localhost:3004'
$env:MCP_AUTH_TOKEN = '<development-token>'
python berlin_mcp_server.py
```

## Available tools

- `check_health`
- `get_metrics_summary`
- `get_performance_metrics`
- `check_slo_compliance`
- `get_level_status`
- `get_mcp_server_stats`

## Azure deployment

Bicep creates:

- `rg-parking-berlin-mcp-{env}`
- `cae-berlin-mcp`
- `ca-berlin-mcp`
- `law-berlin-mcp`
- `appi-parking-berlin-mcp`

The environment uses its own exclusive delegated subnet. Set `deployBerlinMcp=true` and provide `mcpAuthToken` to deploy it.

GitHub Actions uses Azure OIDC and requires:

- Common OIDC variables from [Clean Subscription Deployment Bootstrap](../../docs/DEPLOYMENT_BOOTSTRAP.md)
- `AZURE_CONTAINER_REGISTRY`
- `MCP_AUTH_TOKEN`
- `AZURE_DEPLOYMENTS_ENABLED=true`

The workflow builds and pushes the image, configures the Container App secret, and updates the revision.

## Client configuration

Replace the placeholder host and token with deployment-specific values:

```json
{
  "mcpServers": {
    "berlin-monitoring": {
      "url": "https://berlin-mcp.example.invalid/mcp",
      "transport": "streamable-http",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

## Security

- Use a random token of at least 32 bytes.
- Store the token only in GitHub Secrets or an approved secret store.
- Rotate the token when operators or environments change.
- Do not reuse the token across subscriptions.
- Keep HTTPS ingress enabled.
