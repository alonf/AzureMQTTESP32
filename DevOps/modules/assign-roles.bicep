param functionAppPrincipalId string
param functionAppName string
param storageAccountName string
param serviceBusNamespaceId string

/* storage account role assignment  */

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' existing = {
  name: storageAccountName
}

// Assign Data Contributor role to Managed Identity for Storage Account
resource storageAccountDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountName, functionAppName, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Data Owner role to Managed Identity for Storage Account
resource storageAccountDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountName, functionAppName, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
resource serviceBusDataReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespaceId, functionAppPrincipalId, 'Azure Service Bus Data Receiver')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}


var eventGridTopicSpacesPublisherRoleId = 'a12b0b94-b317-4dcd-84a8-502ce99884c6'
resource  eventGridTopicSpacesPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopicSpacesPublisherRoleId, functionAppPrincipalId, 'Event Grid TopicSpaces Publisher')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventGridTopicSpacesPublisherRoleId)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
