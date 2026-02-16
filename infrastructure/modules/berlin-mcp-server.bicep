// Berlin MCP Server module - Container App for MCP monitoring server
@description('Location for all Berlin MCP resources')
param location string

@description('Environment name (e.g., dev, test, prod)')
param environment string = 'dev'

@description('Berlin API URL to monitor')
param berlinApiUrl string

@description('Container image name')
param containerImage string

@description('Container registry server (leave empty for public registries)')
param containerRegistry string = ''

@description('Container registry name (for ACR role assignment)')
param acrName string = ''

@description('Tags to apply to resources')
param tags object = {}

// Log Analytics Workspace for MCP server monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-berlin-mcp'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-berlin-mcp'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Container App Environment (with Log Analytics integration)
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-berlin-mcp'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Container App (NOT Container Instance)
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-berlin-mcp'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: empty(containerRegistry) ? [] : [
        {
          server: containerRegistry
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'berlin-mcp-server'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'BERLIN_API_URL'
              value: berlinApiUrl
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          probes: [
            {
              type: 'liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// ACR Role Assignment (if using ACR)
module acrAccess 'acr-role-assignment.bicep' = if (!empty(containerRegistry)) {
  name: 'berlin-mcp-acr-access'
  params: {
    principalId: containerApp.identity.principalId
    acrName: acrName
  }
}

// Outputs
output containerAppName string = containerApp.name
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppEnvironmentName string = containerAppEnvironment.name
output appInsightsName string = appInsights.name
output logAnalyticsWorkspaceName string = logAnalytics.name
output containerAppPrincipalId string = containerApp.identity.principalId
