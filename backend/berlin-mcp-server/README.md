# Berlin MCP Server

Model Context Protocol (MCP) server for monitoring the Berlin parking API. Provides tools for health checks, metrics retrieval, and diagnostics.

## Features

The Berlin MCP Server provides 6 monitoring tools:

1. **check_health** - Check the health status of the Berlin parking API
2. **get_metrics_summary** - Get a summary of current metrics
3. **get_parking_status** - Get current parking lot status including availability
4. **check_api_connectivity** - Test connectivity and response time
5. **get_opentelemetry_metrics** - Retrieve OpenTelemetry metrics
6. **diagnose_issues** - Run comprehensive diagnostics

## Architecture

The server runs in two modes:
- **HTTP Mode** (default): Exposes a `/health` endpoint on port 8080 for Container App probes
- **MCP Mode**: Runs as a stdio-based MCP server for integration with MCP clients

## Deployment

The MCP server is deployed as an **Azure Container App** (not Container Instance).

### Resource Names

- **Resource Group**: `rg-parking-berlin-mcp-dev`
- **Container App Environment**: `cae-berlin-mcp`
- **Container App**: `ca-berlin-mcp`
- **Log Analytics**: `law-berlin-mcp`
- **Application Insights**: `ai-berlin-mcp`

### Manual Deployment

```bash
# Deploy infrastructure
az deployment group create \
  --resource-group rg-parking-berlin-mcp-dev \
  --template-file infrastructure/modules/berlin-mcp-server.bicep \
  --parameters \
    location=swedencentral \
    environment=dev \
    berlinApiUrl=https://ca-parking-berlin.braveocean-195c6009.swedencentral.azurecontainerapps.io \
    containerImage=<your-acr>.azurecr.io/berlin-mcp-server:latest \
    containerRegistry=<your-acr>.azurecr.io \
    acrName=<your-acr-name>
```

### Automated Deployment

The server is automatically deployed via GitHub Actions when changes are pushed to `backend/berlin-mcp-server/`:

```bash
git push origin main
```

The workflow:
1. Builds the Docker image
2. Pushes to Azure Container Registry
3. Deploys the Bicep template
4. Updates the Container App

## Environment Variables

- `BERLIN_API_URL` - URL of the Berlin parking API to monitor
- `APPLICATIONINSIGHTS_CONNECTION_STRING` - Application Insights connection string (optional)

## Local Development

### Prerequisites

- Python 3.11+
- Docker (optional, for containerized testing)

### Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Run in HTTP mode (for health checks)
python berlin_mcp_server.py

# Run in MCP mode (stdio)
python berlin_mcp_server.py --mcp
```

### Testing

Test the health endpoint:
```bash
curl http://localhost:8080/health
```

Test MCP tools (requires MCP client):
```bash
# Example using MCP Inspector or similar tool
mcp-inspector berlin_mcp_server.py --mcp
```

## Container Build

```bash
# Build image
docker build -t berlin-mcp-server:latest .

# Run container
docker run -p 8080:8080 \
  -e BERLIN_API_URL=https://ca-parking-berlin.braveocean-195c6009.swedencentral.azurecontainerapps.io \
  berlin-mcp-server:latest

# Test health endpoint
curl http://localhost:8080/health
```

## Monitoring

The server integrates with Azure Application Insights for monitoring and diagnostics. Metrics and traces are automatically sent when `APPLICATIONINSIGHTS_CONNECTION_STRING` is configured.

## Security

- Uses managed identity for ACR authentication
- No admin credentials required
- Application Insights connection string managed as environment variable
- Uses mcp>=1.23.0 to avoid security vulnerabilities

## Dependencies

- `mcp>=1.23.0` - Model Context Protocol SDK
- `httpx>=0.27.0` - HTTP client for API calls
- `fastapi>=0.104.0` - Web framework for health endpoint
- `uvicorn>=0.24.0` - ASGI server
- `opencensus-ext-azure>=1.1.13` - Application Insights integration
