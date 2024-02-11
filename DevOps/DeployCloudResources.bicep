param baseName string
param location string = resourceGroup().location
param userObjectId string = ''
param serviceBusNamespaceName string = '${baseName}sb'
param queueName string = '${baseName}mqttMessageQueue'

var applicationInsightsName = '${baseName}appInsights'
var logAnalyticsWorkspaceName = '${baseName}logAnalytics'

var keyVaultName = '${baseName}keyVault'
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

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault_module'
   params: {
       keyVaultName: keyVaultName
       location: location
       userObjectId: userObjectId
   }
}

// Define Storage Account
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storage-account_module'
  params: {
    name: storageAccountName
    location: location
    
  }
}


module serviceBus 'modules/service-bus.bicep' = {
  name: 'serviceBusModule'
  params: {
    serviceBusNamespaceName: serviceBusNamespaceName
    location: location
    queueName: queueName
  }
}

var queueId = serviceBus.outputs.queueId
var serviceBusNamespaceId = serviceBus.outputs.namespaceId

module eventGrid 'modules/eventgrid.bicep' = {
  name: 'event-grid_module'
  params: {
    baseName: baseName
    location: location
    serviceBusQueueId: queueId
  }
}

var serviceBusEndpoint = 'Endpoint=sb://${serviceBusNamespaceName}.servicebus.windows.net'

var appSettings = [
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
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: serviceBusEndpoint
        }
        {
          name: 'ServiceBusMqttMessageQueueName'
          value: queueName
        }
      ] 


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
    functionAppPrincipalId: managedIdentityId
    functionAppName: functionAppName
    storageAccountName: storageAccountName
    serviceBusNamespaceId: serviceBusNamespaceId
  }
}



