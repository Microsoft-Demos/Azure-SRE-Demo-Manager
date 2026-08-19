// Hub infrastructure module - VNet and Log Analytics Workspace
@description('Location for all hub resources')
param location string

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

@description('Allowed source IP address prefix for SSH/RDP access. Use specific IP ranges in production.')
param allowedSourceIpPrefix string = 'VirtualNetwork'

@description('Tags to apply to resources')
param tags object = {}

// Network Security Group for App Service
resource nsgAppService 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-app-service'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// Network Security Group for VMs
// Note: In production, restrict SSH/RDP access to specific IP ranges using allowedSourceIpPrefix parameter
resource nsgVms 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-vms'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAPIPort3002'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3002'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowAPIPort3003'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3003'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowSSH'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedSourceIpPrefix
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: allowedSourceIpPrefix
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Explicit outbound for private VMs. New VNets don't provide default outbound access.
resource pipVmEgress 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-vm-egress'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 10
  }
}

resource vmNatGateway 'Microsoft.Network/natGateways@2023-05-01' = {
  name: 'ngw-vm-egress'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: pipVmEgress.id
      }
    ]
    idleTimeoutInMinutes: 10
  }
}

// Create Virtual Network (without inline subnets to avoid conflicts on redeployment)
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-parking-hub'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// Create VM subnet as separate resource
resource vmSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-vms'
  properties: {
    addressPrefix: vmSubnetPrefix
    networkSecurityGroup: {
      id: nsgVms.id
    }
    natGateway: {
      id: vmNatGateway.id
    }
  }
}

// Every Container Apps environment requires an exclusive delegated subnet.
resource lisbonContainerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-container-lisbon'
  dependsOn: [
    vmSubnet
  ]
  properties: {
    addressPrefix: lisbonContainerSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.App/environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource berlinContainerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-container-berlin'
  dependsOn: [
    lisbonContainerSubnet
  ]
  properties: {
    addressPrefix: berlinContainerSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.App/environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource chaosContainerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-container-chaos'
  dependsOn: [
    berlinContainerSubnet
  ]
  properties: {
    addressPrefix: chaosContainerSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.App/environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource berlinMcpContainerSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-container-berlin-mcp'
  dependsOn: [
    chaosContainerSubnet
  ]
  properties: {
    addressPrefix: berlinMcpContainerSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.App/environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

// Add App Service subnet with Web Server delegation
resource appServiceSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-app-service'
  dependsOn: [
    berlinMcpContainerSubnet
  ]
  properties: {
    addressPrefix: appServiceSubnetPrefix
    networkSecurityGroup: {
      id: nsgAppService.id
    }
    delegations: [
      {
        name: 'Microsoft.Web/serverFarms'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: vnet
  name: 'snet-private-endpoints'
  dependsOn: [
    appServiceSubnet
  ]
  properties: {
    addressPrefix: privateEndpointSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-parking-hub'
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

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output vmSubnetId string = vmSubnet.id
output lisbonContainerSubnetId string = lisbonContainerSubnet.id
output berlinContainerSubnetId string = berlinContainerSubnet.id
output chaosContainerSubnetId string = chaosContainerSubnet.id
output berlinMcpContainerSubnetId string = berlinMcpContainerSubnet.id
output appServiceSubnetId string = appServiceSubnet.id
output privateEndpointSubnetName string = privateEndpointSubnet.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
output vmNatGatewayId string = vmNatGateway.id
output vmNatGatewayPublicIp string = pipVmEgress.properties.ipAddress
