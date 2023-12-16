param name string
param location string 


// Define Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  #disable-next-line BCP334
  name: name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  properties: {
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output storageAccountId string = storageAccount.id
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

