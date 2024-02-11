param baseName string
param location string 
param serviceBusQueueId string

var namespaceName = '${baseName}ns'
var topicName = '${baseName}mqttMessagesEventGridTopic'
var deviceClientGroupName = '${baseName}DeviceGroup'
var cloudClientGroupName = '${baseName}CloudGroup'

  resource mqttMessagesEventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: topicName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    inputSchema: 'CloudEventSchemaV1_0'
  }
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
    }
    isZoneRedundant: true
    publicNetworkAccess: 'Enabled'
    inboundIpRules: []
  }
}

resource deviceClientGroup 'Microsoft.EventGrid/namespaces/clientGroups@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: deviceClientGroupName
  properties: {
    query: 'attributes.type=\'device\''
  }
}



resource cloudClientGroup 'Microsoft.EventGrid/namespaces/clientGroups@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: cloudClientGroupName
  properties: {
    query: 'attributes.type=\'cloud\''
  }
}


resource cloud2DevicePublisher 'Microsoft.EventGrid/namespaces/permissionBindings@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Cloud2DevicePublisher'
  properties: {
    topicSpaceName: '${baseName}Cloud2Device'
    permission: 'Publisher'
    clientGroupName: cloudClientGroupName
  }
    dependsOn: [
   deviceClientGroup
  ]
}

resource cloud2DeviceSubscriber 'Microsoft.EventGrid/namespaces/permissionBindings@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Cloud2DeviceSubscriber'
  properties: {
    topicSpaceName: '${baseName}Cloud2Device'
    permission: 'Subscriber'
    clientGroupName: deviceClientGroupName 
  }
  dependsOn: [
   cloudClientGroup
  ]
}

resource device2CloudPublisher 'Microsoft.EventGrid/namespaces/permissionBindings@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Device2CloudPublisher'
  properties: {
    topicSpaceName: '${baseName}Device2Cloud'
    permission: 'Publisher'
    clientGroupName: deviceClientGroupName
  }
    dependsOn: [
   deviceClientGroup
  ]
}

resource device2CloudSubscriber 'Microsoft.EventGrid/namespaces/permissionBindings@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Device2CloudSubscriber'
  properties: {
    topicSpaceName: '${baseName}Device2Cloud'
    permission: 'Subscriber'
    clientGroupName: cloudClientGroupName 
  }
  dependsOn: [
   deviceClientGroup
  ]
}

resource cloud2DeviceTopicSpace 'Microsoft.EventGrid/namespaces/topicSpaces@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Cloud2Device'
  properties: {
    topicTemplates: [
      'device/+/twin/desired/#'
      'device/+/commands/#'
      'device/+/responses/#'
    ]
  }
}

resource device2CloudTopicSpace 'Microsoft.EventGrid/namespaces/topicSpaces@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Device2Cloud'
  properties: {
    topicTemplates: [
      'device/+/twin/reported/#'
      'device/+/telemetry/#'
      'device/+/responses/#'
    ]
  }
}



var eventDataSenderRoleId = 'd5a91429-5739-47e2-a06b-3470a27159e7'

resource eventGridNamespaceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridNamespace.id, eventDataSenderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventDataSenderRoleId)
    principalId: eventGridNamespace.identity.principalId
    principalType: 'ServicePrincipal'
  }
  scope: mqttMessagesEventGridTopic
}


resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: '${baseName}sbQueueSubscription'
  scope: mqttMessagesEventGridTopic
  properties: {
    destination: {
      endpointType: 'ServiceBusQueue'
      properties: {
        resourceId: serviceBusQueueId
      }
    }
    // filter: {
    //   subjectBeginsWith: ''
    // }
  }
}
