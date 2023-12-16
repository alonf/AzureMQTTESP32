param keyVaultName string
param location string

// Define Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName // KeyVault should be purge or recovered manualy after resourceGroup was deleting (keyVault -> manage deleted vault) 
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    accessPolicies: []
  }
}



