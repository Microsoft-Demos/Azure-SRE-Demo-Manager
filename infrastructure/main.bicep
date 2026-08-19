// Main Bicep file for Azure SRE Demo Manager Infrastructure
targetScope = 'subscription'

@description('Primary location for all resources')
param location string = 'swedencentral'

@description('Environment name (e.g., dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Admin username for VMs')
param adminUsername string

@description('Admin password for VMs')
@secure()
param adminPassword string

@description('Container image for Lisbon API')
param lisbonContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container image for Berlin API')
param berlinContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container image for Chaos Control')
param chaosControlContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container image for VM Health Control')
param vmHealthControlContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container registry server (if using private registry)')
param containerRegistry string = ''

@description('Create public IPs for VMs')
param createPublicIps bool = false

@description('Deploy or skip the Madrid VM and its extensions')
param deployMadridVm bool = true

@description('Deploy or skip the Paris VM and its extensions')
param deployParisVm bool = true

@description('Deploy or skip the Berlin MCP server')
param deployBerlinMcp bool = false

@description('Virtual Network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix for VMs')
param vmSubnetPrefix string = '10.0.1.0/24'

@description('Exclusive subnet address prefix for the Lisbon Container Apps environment')
param lisbonContainerSubnetPrefix string = '10.0.2.0/27'

@description('Exclusive subnet address prefix for the Berlin Container Apps environment')
param berlinContainerSubnetPrefix string = '10.0.2.32/27'

@description('Exclusive subnet address prefix for the Chaos Container Apps environment')
param chaosContainerSubnetPrefix string = '10.0.2.64/27'

@description('Exclusive subnet address prefix for the Berlin MCP Container Apps environment')
param berlinMcpContainerSubnetPrefix string = '10.0.2.96/27'

@description('Subnet address prefix for App Service VNet integration')
param appServiceSubnetPrefix string = '10.0.5.0/24'

@description('Subnet address prefix for private endpoints')
param privateEndpointSubnetPrefix string = '10.0.6.0/27'

@description('Allowed source IP address prefix for SSH/RDP access (use specific IPs in production)')
param allowedSourceIpPrefix string = 'VirtualNetwork'

@description('Create a private Azure Container Registry')
param createContainerRegistry bool = true

@description('Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('GitHub application deployment service principal object ID')
param applicationPrincipalId string = ''

@description('Authentication token for the optional Berlin MCP server')
@secure()
param mcpAuthToken string = ''

// Common tags
var tags = {
  Environment: environment
  Project: 'Azure-SRE-Demo-Manager'
  ManagedBy: 'Bicep'
}

// Resource Group names
var hubRgName = 'rg-parking-hub-${environment}'
var frontendRgName = 'rg-parking-frontend-${environment}'
var lisbonRgName = 'rg-parking-lisbon-${environment}'
var madridRgName = 'rg-parking-madrid-${environment}'
var parisRgName = 'rg-parking-paris-${environment}'
var berlinRgName = 'rg-parking-berlin-${environment}'
var chaosControlRgName = 'rg-parking-chaos-${environment}'
var berlinMcpRgName = 'rg-parking-berlin-mcp-${environment}'

// ========================================
// Resource Groups
// ========================================

resource hubRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: hubRgName
  location: location
  tags: tags
}

resource frontendRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: frontendRgName
  location: location
  tags: tags
}

resource lisbonRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: lisbonRgName
  location: location
  tags: tags
}

resource madridRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: madridRgName
  location: location
  tags: tags
}

resource parisRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: parisRgName
  location: location
  tags: tags
}

resource berlinRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: berlinRgName
  location: location
  tags: tags
}

resource chaosControlRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: chaosControlRgName
  location: location
  tags: tags
}

resource berlinMcpRg 'Microsoft.Resources/resourceGroups@2023-07-01' = if (deployBerlinMcp) {
  name: berlinMcpRgName
  location: location
  tags: tags
}

// ========================================
// Hub Infrastructure (VNet + Log Analytics)
// ========================================

module hub 'modules/hub.bicep' = {
  scope: hubRg
  name: 'hub-deployment'
  params: {
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    vmSubnetPrefix: vmSubnetPrefix
    lisbonContainerSubnetPrefix: lisbonContainerSubnetPrefix
    berlinContainerSubnetPrefix: berlinContainerSubnetPrefix
    chaosContainerSubnetPrefix: chaosContainerSubnetPrefix
    berlinMcpContainerSubnetPrefix: berlinMcpContainerSubnetPrefix
    appServiceSubnetPrefix: appServiceSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    allowedSourceIpPrefix: allowedSourceIpPrefix
    tags: tags
  }
}

// ========================================
// Deployment Storage Account (for CI/CD)
// ========================================

module deploymentStorage 'modules/deployment-storage.bicep' = {
  scope: hubRg
  name: 'deployment-storage'
  params: {
    location: location
    tags: tags
  }
}

// Private endpoint for deployment storage (blob) and private DNS linking
module storagePrivateEndpoint 'modules/storage-private-endpoint.bicep' = {
  scope: hubRg
  name: 'deployment-storage-private-endpoint'
  params: {
    location: location
    vnetName: hub.outputs.vnetName
    subnetName: hub.outputs.privateEndpointSubnetName
    storageAccountId: deploymentStorage.outputs.storageAccountId
    tags: tags
  }
}

// Grant GitHub Actions SP access to deployment storage
module spStorageAccess 'modules/sp-storage-access.bicep' = if (!empty(applicationPrincipalId)) {
  scope: hubRg
  name: 'sp-storage-access'
  params: {
    principalId: applicationPrincipalId
    storageAccountId: deploymentStorage.outputs.storageAccountId
  }
}

// ========================================
// Container Registry
// ========================================

module acr 'modules/container-registry.bicep' = if (createContainerRegistry) {
  scope: hubRg
  name: 'container-registry-deployment'
  params: {
    location: location
    environment: environment
    sku: containerRegistrySku
    adminUserEnabled: false
    tags: tags
  }
}

module githubActionsAcrPush 'modules/acr-role-assignment.bicep' = if (createContainerRegistry && !empty(applicationPrincipalId)) {
  scope: hubRg
  name: 'github-actions-acr-push'
  params: {
    principalId: applicationPrincipalId
    acrName: acr!.outputs.registryName
    roleDefinitionId: '8311e382-0749-4cb8-b61a-304f252e45ec' // AcrPush
  }
}

module applicationHubAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: hubRg
  name: 'application-hub-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationFrontendAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: frontendRg
  name: 'application-frontend-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationLisbonAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: lisbonRg
  name: 'application-lisbon-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationBerlinAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: berlinRg
  name: 'application-berlin-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationChaosAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: chaosControlRg
  name: 'application-chaos-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationMadridAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: madridRg
  name: 'application-madrid-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationParisAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId)) {
  scope: parisRg
  name: 'application-paris-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

module applicationBerlinMcpAccess 'modules/resource-group-role-assignment.bicep' = if (!empty(applicationPrincipalId) && deployBerlinMcp) {
  scope: berlinMcpRg
  name: 'application-berlin-mcp-contributor'
  params: {
    principalId: applicationPrincipalId
  }
}

// ========================================
// Lisbon API (Container App)
// ========================================

module lisbonApi 'modules/lisbon-api.bicep' = {
  scope: lisbonRg
  name: 'lisbon-api-deployment'
  params: {
    location: location
    containerSubnetId: hub.outputs.lisbonContainerSubnetId
    logAnalyticsWorkspaceId: hub.outputs.logAnalyticsWorkspaceId
    logAnalyticsCustomerId: hub.outputs.logAnalyticsCustomerId
    containerImage: lisbonContainerImage
    containerRegistry: createContainerRegistry ? acr!.outputs.loginServer : containerRegistry
    chaosControlUrl: chaosControl.outputs.containerAppUrl
    tags: tags
  }
}

// Grant Container App access to ACR
module lisbonAcrAccess 'modules/acr-role-assignment.bicep' = if (createContainerRegistry) {
  scope: hubRg
  name: 'lisbon-acr-access'
  params: {
    principalId: lisbonApi.outputs.containerAppPrincipalId
    acrName: acr!.outputs.registryName
  }
}

// ========================================
// Berlin API (Container App)
// ========================================

module berlinApi 'modules/berlin-api.bicep' = {
  scope: berlinRg
  name: 'berlin-api-deployment'
  params: {
    location: location
    containerSubnetId: hub.outputs.berlinContainerSubnetId
    containerImage: berlinContainerImage
    containerRegistry: createContainerRegistry ? acr!.outputs.loginServer : containerRegistry
    chaosControlUrl: chaosControl.outputs.containerAppUrl
    tags: tags
  }
}

// Grant Container App access to ACR
module berlinAcrAccess 'modules/acr-role-assignment.bicep' = if (createContainerRegistry) {
  scope: hubRg
  name: 'berlin-acr-access'
  params: {
    principalId: berlinApi.outputs.containerAppPrincipalId
    acrName: acr!.outputs.registryName
  }
}

// ========================================
// Chaos Control (Container App)
// ========================================

module chaosControl 'modules/chaos-control.bicep' = {
  scope: chaosControlRg
  name: 'chaos-control-deployment'
  params: {
    location: location
    environment: environment
    containerSubnetId: hub.outputs.chaosContainerSubnetId
    containerImage: chaosControlContainerImage
    containerRegistry: createContainerRegistry ? acr!.outputs.loginServer : containerRegistry
    tags: tags
  }
}

// Grant Container App access to ACR
module chaosControlAcrAccess 'modules/acr-role-assignment.bicep' = if (createContainerRegistry) {
  scope: hubRg
  name: 'chaos-control-acr-access'
  params: {
    principalId: chaosControl.outputs.containerAppPrincipalId
    acrName: acr!.outputs.registryName
  }
}

// ========================================
// VM Health Control (Container App)
// ========================================

module vmHealthTable 'modules/vm-health-table.bicep' = {
  scope: hubRg
  name: 'vm-health-table-deployment'
  params: {
    workspaceName: hub.outputs.logAnalyticsWorkspaceName
  }
}

module vmHealthControl 'modules/vm-health-control.bicep' = {
  scope: chaosControlRg
  name: 'vm-health-control-deployment'
  dependsOn: [ vmHealthTable ]
  params: {
    location: location
    containerAppEnvironmentId: chaosControl.outputs.containerAppEnvironmentId
    containerImage: vmHealthControlContainerImage
    containerRegistry: createContainerRegistry ? acr!.outputs.loginServer : containerRegistry
    logAnalyticsWorkspaceId: hub.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

// Grant Container App access to ACR
module vmHealthControlAcrAccess 'modules/acr-role-assignment.bicep' = if (createContainerRegistry) {
  scope: hubRg
  name: 'vm-health-control-acr-access'
  params: {
    principalId: vmHealthControl.outputs.containerAppPrincipalId
    acrName: acr!.outputs.registryName
  }
}

// VM Health Alerts (scheduled query rules on VMHealthStatus_CL)
module vmHealthAlerts 'modules/vm-health-alerts.bicep' = {
  scope: hubRg
  name: 'vm-health-alerts-deployment'
  dependsOn: [ vmHealthTable ]
  params: {
    location: location
    logAnalyticsWorkspaceId: hub.outputs.logAnalyticsWorkspaceId
  }
}

// ========================================
// Berlin MCP Server (Container App for monitoring Berlin API)
// ========================================

module berlinMcpServer 'modules/berlin-mcp-server.bicep' = if (deployBerlinMcp) {
  scope: berlinMcpRg
  name: 'berlin-mcp-server-deployment'
  params: {
    location: location
    containerSubnetId: hub.outputs.berlinMcpContainerSubnetId
    berlinApiUrl: berlinApi.outputs.containerAppUrl
    containerImage: '' // Will be set by CI/CD pipeline
    containerRegistry: createContainerRegistry ? acr!.outputs.loginServer : containerRegistry
    mcpAuthToken: mcpAuthToken
    tags: tags
  }
}

// Grant Berlin MCP Server Container App access to ACR
module berlinMcpAcrAccess 'modules/acr-role-assignment.bicep' = if (createContainerRegistry && deployBerlinMcp) {
  scope: hubRg
  name: 'berlin-mcp-acr-access'
  params: {
    principalId: berlinMcpServer!.outputs.containerAppPrincipalId
    acrName: acr!.outputs.registryName
  }
}

// ========================================
// Madrid API (Windows Server VM)
// ========================================

module madridApi 'modules/madrid-api.bicep' = {
  scope: madridRg
  name: 'madrid-api-deployment'
  params: {
    location: location
    vmSubnetId: hub.outputs.vmSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    createPublicIp: createPublicIps
    deployVM: deployMadridVm
    tags: tags
  }
}

// ========================================
// Paris API (Ubuntu Server VM)
// ========================================

module parisApi 'modules/paris-api.bicep' = {
  scope: parisRg
  name: 'paris-api-deployment'
  params: {
    location: location
    vmSubnetId: hub.outputs.vmSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    createPublicIp: createPublicIps
    deployVM: deployParisVm
    tags: tags
  }
}

// ========================================
// VM Log Collection (AMA + DCR)
// ========================================

module vmLogCollection 'modules/data-collection-rules.bicep' = {
  scope: hubRg
  name: 'vm-log-collection-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceId: hub.outputs.logAnalyticsWorkspaceId
    deployMadridVm: deployMadridVm
    deployParisVm: deployParisVm
    tags: tags
  }
}

module madridDcrAssociation 'modules/vm-dcr-association.bicep' = if (deployMadridVm) {
  scope: madridRg
  name: 'madrid-dcr-association-deployment'
  params: {
    vmName: madridApi.outputs.vmName
    associationName: 'assoc-madrid-windows-events'
    associationDescription: 'Collect Madrid Windows Event Viewer logs to Log Analytics'
    dataCollectionRuleId: vmLogCollection.outputs.madridWindowsEventsDcrId
    dataCollectionEndpointId: vmLogCollection.outputs.dataCollectionEndpointId
  }
}

module parisDcrAssociation 'modules/vm-dcr-association.bicep' = if (deployParisVm) {
  scope: parisRg
  name: 'paris-dcr-association-deployment'
  params: {
    vmName: parisApi.outputs.vmName
    associationName: 'assoc-paris-syslog'
    associationDescription: 'Collect Paris Linux syslog logs to Log Analytics'
    dataCollectionRuleId: vmLogCollection.outputs.parisSyslogDcrId
    dataCollectionEndpointId: vmLogCollection.outputs.dataCollectionEndpointId
  }
}

// ========================================
// Frontend (React App on App Service)
// ========================================

module frontend 'modules/frontend.bicep' = {
  scope: frontendRg
  name: 'frontend-deployment'
  params: {
    location: location
    appServiceSubnetId: hub.outputs.appServiceSubnetId
    logAnalyticsWorkspaceId: hub.outputs.logAnalyticsWorkspaceId
    lisbonApiUrl: lisbonApi.outputs.containerAppUrl
    madridApiUrl: madridApi.outputs.apiUrl
    parisApiUrl: parisApi.outputs.apiUrl
    berlinApiUrl: berlinApi.outputs.containerAppUrl
    chaosControlUrl: chaosControl.outputs.containerAppUrl
    vmHealthControlUrl: vmHealthControl.outputs.containerAppUrl
    tags: tags
  }
}

// ========================================
// Outputs
// ========================================

output hubResourceGroup string = hubRg.name
output frontendResourceGroup string = frontendRg.name
output lisbonResourceGroup string = lisbonRg.name
output madridResourceGroup string = madridRg.name
output parisResourceGroup string = parisRg.name
output berlinResourceGroup string = berlinRg.name
output chaosControlResourceGroup string = chaosControlRg.name
output berlinMcpResourceGroup string = deployBerlinMcp ? berlinMcpRg!.name : ''

output vnetName string = hub.outputs.vnetName
output appServiceSubnetPrefix string = appServiceSubnetPrefix
output logAnalyticsWorkspaceId string = hub.outputs.logAnalyticsWorkspaceId
output logAnalyticsWorkspaceName string = hub.outputs.logAnalyticsWorkspaceName

output containerRegistryName string = createContainerRegistry ? acr!.outputs.registryName : ''
output containerRegistryLoginServer string = createContainerRegistry ? acr!.outputs.loginServer : ''
output containerRegistryUrl string = createContainerRegistry ? acr!.outputs.registryUrl : ''

output deploymentStorageAccountName string = deploymentStorage.outputs.storageAccountName
output deploymentStorageBlobEndpoint string = deploymentStorage.outputs.blobEndpoint

output frontendUrl string = frontend.outputs.appServiceUrl
output frontendAppServiceName string = frontend.outputs.appServiceName
output lisbonApiUrl string = lisbonApi.outputs.containerAppUrl
output madridApiUrl string = madridApi.outputs.apiUrl
output parisApiUrl string = parisApi.outputs.apiUrl
output berlinApiUrl string = berlinApi.outputs.containerAppUrl
output chaosControlUrl string = chaosControl.outputs.containerAppUrl
output chaosControlContainerAppName string = chaosControl.outputs.containerAppName
output vmHealthControlUrl string = vmHealthControl.outputs.containerAppUrl
output vmHealthControlContainerAppName string = vmHealthControl.outputs.containerAppName
output berlinMcpServerUrl string = deployBerlinMcp ? berlinMcpServer!.outputs.mcpServerUrl : ''
output berlinMcpAppInsightsName string = deployBerlinMcp ? berlinMcpServer!.outputs.appInsightsName : ''
output berlinMcpLogAnalyticsWorkspaceName string = deployBerlinMcp ? berlinMcpServer!.outputs.logAnalyticsWorkspaceName : ''
output berlinMcpContainerAppName string = deployBerlinMcp ? berlinMcpServer!.outputs.containerAppName : ''

output madridVmName string = madridApi.outputs.vmName
output madridPublicIp string = madridApi.outputs.publicIpAddress
output madridFqdn string = madridApi.outputs.fqdn

output parisVmName string = parisApi.outputs.vmName
output parisPublicIp string = parisApi.outputs.publicIpAddress
output parisFqdn string = parisApi.outputs.fqdn

output dataCollectionEndpointId string = vmLogCollection.outputs.dataCollectionEndpointId
output madridWindowsEventsDcrId string = vmLogCollection.outputs.madridWindowsEventsDcrId
output parisSyslogDcrId string = vmLogCollection.outputs.parisSyslogDcrId
