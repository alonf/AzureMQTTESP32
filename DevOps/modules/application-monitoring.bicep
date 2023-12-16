param applicationInsightsName string
param logAnalyticsWorkspaceName string
param location string 
param logRetentionInDays int

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
  }
}

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output InstrumentationKey string= applicationInsights.properties.InstrumentationKey
