param baseName string
param location string = resourceGroup().location

param servicePrincipalId string = ''
@secure()
param servicePrincipalSecret string = ''
param servicePrincipalObjectId string = ''
param tenantId string = ''

var applicationInsightsName = '${baseName}appInsights'
var logAnalyticsWorkspaceName = '${baseName}logAnalytics'


var functionAppDiagnosticsName = '${baseName}functionAppDiagnostics'
var logRetentionInDays = 30
var storageAccountName = '${baseName}sa'
var functionAppName = '${baseName}FunctionApp'

// Define monitoring and logging module
module applicationMonitoring 'modules/application-monitoring.bicep' = {
  name: 'application-monitoring_module'
  params: {
    applicationInsightsName: applicationInsightsName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
    logRetentionInDays: logRetentionInDays
  }
}
var logAnalyticsWorkspaceId = applicationMonitoring.outputs.logAnalyticsWorkspaceId
var insightsInstrumentationKey = applicationMonitoring.outputs.InstrumentationKey


// Define Storage Account
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storage-account_module'
  params: {
    name: storageAccountName
    location: location
    
  }
}

module eventGrid 'modules/eventgrid.bicep' = {
  name: 'event-grid_module'
  params: {
    baseName: baseName
    location: location
  }
}

var conditionalAppSettings = !empty(servicePrincipalId) ? [
  {
    name: 'AZURE_CLIENT_ID'
    value: servicePrincipalId
  }
  {
    name: 'AZURE_CLIENT_SECRET'
    value: servicePrincipalSecret
  }
  {
    name: 'AZURE_TENANT_ID'
    value: tenantId
  }
] : [] // If servicePrincipalId is empty, this will be an empty array


var coreAppSettings = [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: insightsInstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName 
        }
        {
          name: 'SubscriptionId'
          value: subscription().subscriptionId
        }
        {
          name: 'ResourceGroup'
          value: resourceGroup().name
        }
      ] 

var appSettings = union(coreAppSettings, conditionalAppSettings)

resource AzureFunction 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp' // Use 'functionapp,linux' for Linux-based functions
  properties: {
    siteConfig: {
     appSettings: appSettings 
     cors: {
        allowedOrigins: [
          '*' // Allow all origins
         ]
        supportCredentials: false // Set to true if your application requires credentials in CORS requests
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

var managedIdentityId = AzureFunction.identity.principalId
var functionAppPrincipalId = !empty(servicePrincipalId) ? servicePrincipalObjectId : managedIdentityId

resource functionAppDiagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: AzureFunction
  name: functionAppDiagnosticsName
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
      }
      // Additional log categories as needed
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

module assignRoles 'modules/assign-roles.bicep' = {
  name: 'assign-roles-module'
  params: {
    functionAppPrincipalId: functionAppPrincipalId
    functionAppName: functionAppName
    storageAccountName: storageAccountName
  }
}



