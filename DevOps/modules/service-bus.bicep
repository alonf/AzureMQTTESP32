param serviceBusNamespaceName string
param location string
param sku string = 'Basic' // Default to Standard. Other options: Basic, Premium
param queueName string

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: sku
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: queueName
  properties: {}
}

output namespaceId string = serviceBusNamespace.id
output queueId string = serviceBusQueue.id
