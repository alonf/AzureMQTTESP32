param baseName string
param location string 

var namespaceName = '${baseName}ns'
var topicName = '${baseName}Topic'
var devicetClientGroupName = '${baseName}DeviceGroup'
var cloudClientGroupName = '${baseName}CloudGroup'


resource eventGridNamespace 'Microsoft.EventGrid/namespaces@2023-12-15-preview' = {
#disable-next-line BCP334
  name: namespaceName
  location: location
  sku: {
    name: 'Standard'
    capacity: 1
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

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: topicName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    inputSchema: 'CloudEventSchemaV1_0'
  }
}

resource deviceClientGroup 'Microsoft.EventGrid/namespaces/clientGroups@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: devicetClientGroupName
  properties: {
    query: 'attributes.type=\'esp32\''
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
    clientGroupName: cloudClientGroupName
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
    clientGroupName: devicetClientGroupName
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
    clientGroupName: deviceClientGroupName
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
      'device/+/twin/desired'
      'device/+/commands'
      'device/+/responses'
    ]
  }
}

resource device2CloudTopicSpace 'Microsoft.EventGrid/namespaces/topicSpaces@2023-12-15-preview' = {
  parent: eventGridNamespace
  name: '${baseName}Device2Cloud'
  properties: {
    topicTemplates: [
      'device/+/twin/reported'
      'device/+/telemetry'
      'device/+/responses'
    ]
  }
}

//output bane string = value