param baseName string
param location string = resourceGroup().location
var namespaceName = '${baseName}ns'


  resource mqttMessagesEventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' existing = {
  name: '${baseName}mqttMessagesEventGridTopic'
  }

resource eventGridNamespace 'Microsoft.EventGrid/namespaces@2023-12-15-preview' = {
#disable-next-line BCP334
  name: namespaceName
  location: location
  sku: {
    name: 'Standard'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned' // Add a system-assigned managed identity to the Event Grid namespace.
  }
  properties: {
    topicSpacesConfiguration: {
      state: 'Enabled'
      maximumSessionExpiryInHours: 8
      maximumClientSessionsPerAuthenticationName: 1
      routeTopicResourceId: mqttMessagesEventGridTopic.id
      routingIdentityInfo: {
        type: 'SystemAssigned'
      }
    }
    isZoneRedundant: true
    publicNetworkAccess: 'Enabled'
    inboundIpRules: []
  }
}