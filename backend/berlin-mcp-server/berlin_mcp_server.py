"""
Berlin MCP Server - Model Context Protocol server for monitoring Berlin parking API
Provides tools for health checks, metrics retrieval, and diagnostics
"""
import asyncio
import os
from datetime import datetime
from typing import Any, Dict

import httpx
from fastapi import FastAPI
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
from opencensus.ext.azure import metrics_exporter

# Environment configuration
BERLIN_API_URL = os.getenv('BERLIN_API_URL', 'https://ca-parking-berlin.braveocean-195c6009.swedencentral.azurecontainerapps.io')
APPINSIGHTS_CONNECTION_STRING = os.getenv('APPLICATIONINSIGHTS_CONNECTION_STRING', '')

# Create FastAPI app for health endpoint
fastapi_app = FastAPI(title="Berlin MCP Server", version="1.0.0")

@fastapi_app.get("/health")
async def health_check():
    """Health check endpoint for Container App probes"""
    return {
        "status": "healthy",
        "service": "berlin-mcp-server",
        "timestamp": datetime.now().isoformat(),
        "berlin_api_url": BERLIN_API_URL
    }

# Create MCP Server
mcp_server = Server("berlin-mcp-server")

# HTTP client for API calls
http_client = httpx.AsyncClient(timeout=30.0)


@mcp_server.list_tools()
async def list_tools() -> list[Tool]:
    """List all available MCP tools for Berlin parking API monitoring"""
    return [
        Tool(
            name="check_health",
            description="Check the health status of the Berlin parking API",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_metrics_summary",
            description="Get a summary of current metrics from the Berlin parking API",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_parking_status",
            description="Get current parking lot status including availability and occupancy",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="check_api_connectivity",
            description="Test connectivity and response time to the Berlin parking API",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_opentelemetry_metrics",
            description="Retrieve OpenTelemetry metrics from the Berlin parking API",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="diagnose_issues",
            description="Run comprehensive diagnostics to identify potential issues with the Berlin API",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        )
    ]


@mcp_server.call_tool()
async def call_tool(name: str, arguments: Dict[str, Any]) -> list[TextContent]:
    """Handle tool execution requests"""
    
    if name == "check_health":
        return await check_health()
    elif name == "get_metrics_summary":
        return await get_metrics_summary()
    elif name == "get_parking_status":
        return await get_parking_status()
    elif name == "check_api_connectivity":
        return await check_api_connectivity()
    elif name == "get_opentelemetry_metrics":
        return await get_opentelemetry_metrics()
    elif name == "diagnose_issues":
        return await diagnose_issues()
    else:
        return [TextContent(type="text", text=f"Unknown tool: {name}")]


async def check_health() -> list[TextContent]:
    """Check health status of Berlin parking API"""
    try:
        response = await http_client.get(f"{BERLIN_API_URL}/health")
        response.raise_for_status()
        data = response.json()
        
        status = "✅ HEALTHY" if response.status_code == 200 else "⚠️ DEGRADED"
        result = f"""
Berlin Parking API Health Check
Status: {status}
Response Time: {response.elapsed.total_seconds():.3f}s
Details: {data}
        """
        return [TextContent(type="text", text=result.strip())]
    except Exception as e:
        return [TextContent(type="text", text=f"❌ Health check failed: {str(e)}")]


async def get_metrics_summary() -> list[TextContent]:
    """Get metrics summary from Berlin parking API"""
    try:
        response = await http_client.get(f"{BERLIN_API_URL}/metrics")
        response.raise_for_status()
        data = response.json()
        
        result = f"""
Berlin Parking API Metrics Summary
----------------------------------
Total Requests: {data.get('totalRequests', 0)}
Total Errors: {data.get('totalErrors', 0)}
Average Response Time: {data.get('avgResponseTime', 0):.2f}ms
Current Spaces: {data.get('currentSpaces', 'N/A')}
Total Capacity: {data.get('totalCapacity', 'N/A')}
Occupancy Rate: {data.get('occupancyRate', 0):.1f}%
        """
        return [TextContent(type="text", text=result.strip())]
    except Exception as e:
        return [TextContent(type="text", text=f"❌ Failed to retrieve metrics: {str(e)}")]


async def get_parking_status() -> list[TextContent]:
    """Get current parking lot status"""
    try:
        response = await http_client.get(f"{BERLIN_API_URL}/parking")
        response.raise_for_status()
        data = response.json()
        
        available = data.get('availableSpaces', 0)
        total = data.get('totalCapacity', 0)
        occupancy = ((total - available) / total * 100) if total > 0 else 0
        
        result = f"""
Berlin Parking Status
--------------------
Location: {data.get('location', 'Unknown')}
Available Spaces: {available} / {total}
Occupancy: {occupancy:.1f}%
Status: {'🟢 Available' if available > 10 else '🟡 Limited' if available > 0 else '🔴 Full'}
Last Updated: {data.get('timestamp', 'Unknown')}
        """
        return [TextContent(type="text", text=result.strip())]
    except Exception as e:
        return [TextContent(type="text", text=f"❌ Failed to retrieve parking status: {str(e)}")]


async def check_api_connectivity() -> list[TextContent]:
    """Test API connectivity and response times"""
    try:
        start = datetime.now()
        response = await http_client.get(f"{BERLIN_API_URL}/health")
        end = datetime.now()
        
        response_time = (end - start).total_seconds() * 1000
        
        result = f"""
Berlin API Connectivity Test
---------------------------
Status: {'✅ Connected' if response.status_code == 200 else '❌ Failed'}
Response Time: {response_time:.2f}ms
HTTP Status: {response.status_code}
Endpoint: {BERLIN_API_URL}
        """
        return [TextContent(type="text", text=result.strip())]
    except Exception as e:
        return [TextContent(type="text", text=f"❌ Connectivity test failed: {str(e)}")]


async def get_opentelemetry_metrics() -> list[TextContent]:
    """Retrieve OpenTelemetry metrics from Berlin API"""
    try:
        response = await http_client.get(f"{BERLIN_API_URL}/metrics/opentelemetry")
        response.raise_for_status()
        data = response.json()
        
        # Parse OpenTelemetry data
        resource_metrics = data.get('resourceMetrics', [])
        if not resource_metrics:
            return [TextContent(type="text", text="No OpenTelemetry metrics available")]
        
        metrics_text = "Berlin API OpenTelemetry Metrics\n================================\n\n"
        
        for rm in resource_metrics:
            scope_metrics = rm.get('scopeMetrics', [])
            for sm in scope_metrics:
                for metric in sm.get('metrics', []):
                    name = metric.get('name', 'unknown')
                    description = metric.get('description', '')
                    
                    # Handle different metric types
                    if 'sum' in metric:
                        data_points = metric['sum'].get('dataPoints', [])
                        for dp in data_points:
                            value = dp.get('asInt', dp.get('asDouble', 'N/A'))
                            metrics_text += f"• {name}: {value}\n"
                            if description:
                                metrics_text += f"  Description: {description}\n"
                    elif 'gauge' in metric:
                        data_points = metric['gauge'].get('dataPoints', [])
                        for dp in data_points:
                            value = dp.get('asInt', dp.get('asDouble', 'N/A'))
                            metrics_text += f"• {name}: {value}\n"
                            if description:
                                metrics_text += f"  Description: {description}\n"
        
        return [TextContent(type="text", text=metrics_text.strip())]
    except Exception as e:
        return [TextContent(type="text", text=f"❌ Failed to retrieve OpenTelemetry metrics: {str(e)}")]


async def diagnose_issues() -> list[TextContent]:
    """Run comprehensive diagnostics on Berlin API"""
    diagnostics = []
    
    # Check health
    try:
        health_response = await http_client.get(f"{BERLIN_API_URL}/health")
        health_status = "✅ Healthy" if health_response.status_code == 200 else "❌ Unhealthy"
        diagnostics.append(f"Health Check: {health_status}")
    except Exception as e:
        diagnostics.append(f"Health Check: ❌ Failed - {str(e)}")
    
    # Check metrics endpoint
    try:
        metrics_response = await http_client.get(f"{BERLIN_API_URL}/metrics")
        metrics_status = "✅ Available" if metrics_response.status_code == 200 else "❌ Unavailable"
        diagnostics.append(f"Metrics Endpoint: {metrics_status}")
    except Exception as e:
        diagnostics.append(f"Metrics Endpoint: ❌ Failed - {str(e)}")
    
    # Check parking endpoint
    try:
        parking_response = await http_client.get(f"{BERLIN_API_URL}/parking")
        parking_status = "✅ Available" if parking_response.status_code == 200 else "❌ Unavailable"
        diagnostics.append(f"Parking Endpoint: {parking_status}")
    except Exception as e:
        diagnostics.append(f"Parking Endpoint: ❌ Failed - {str(e)}")
    
    # Check OpenTelemetry metrics
    try:
        otel_response = await http_client.get(f"{BERLIN_API_URL}/metrics/opentelemetry")
        otel_status = "✅ Available" if otel_response.status_code == 200 else "❌ Unavailable"
        diagnostics.append(f"OpenTelemetry Metrics: {otel_status}")
    except Exception as e:
        diagnostics.append(f"OpenTelemetry Metrics: ❌ Failed - {str(e)}")
    
    result = "Berlin API Diagnostics Report\n" + "="*30 + "\n" + "\n".join(diagnostics)
    return [TextContent(type="text", text=result)]


async def run_mcp_server():
    """Run the MCP server using stdio transport"""
    async with stdio_server() as (read_stream, write_stream):
        await mcp_server.run(
            read_stream,
            write_stream,
            mcp_server.create_initialization_options()
        )


if __name__ == "__main__":
    import sys
    import uvicorn
    
    # Check if running as MCP server (stdio mode) or HTTP server
    if len(sys.argv) > 1 and sys.argv[1] == "--mcp":
        # Run MCP server in stdio mode
        asyncio.run(run_mcp_server())
    else:
        # Run FastAPI app for health checks and HTTP endpoints
        uvicorn.run(fastapi_app, host="0.0.0.0", port=8080)
