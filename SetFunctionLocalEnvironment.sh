#!/bin/bash

# Check for base name argument
if [ -z "$1" ]; then
    echo "Usage: $0 <BaseName>"
    exit 1
fi

# Assign base name argument
BaseName=$1

# Define the resource group name
rgName="${BaseName}rg"

serviceBusNamespaceName="${BaseName}sb"
queueName="${BaseName}mqttMessageQueue"

# Ensure user is logged into Azure and has chosen a subscription
az account show > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Not logged in to Azure or no subscription selected. Please log in and select a subscription."
    exit 1
fi

# Get the current subscription ID
subscriptionId=$(az account show --query "id" -o tsv)

# Check if the resource group exists
rgExists=$(az group exists --name $rgName)

if [ "$rgExists" = "false" ]; then
    echo "Resource group $rgName does not exist. Please create the resource group first."
    exit 1
fi



# Check if the service principal exists
spName="${BaseName}-sp"

# Retrieve the application (client) ID of the service principal
spAppId=$(az ad sp list --display-name "$spName" --query "[].appId" -o tsv)

if [ -z "$spAppId" ]; then
    echo "Service principal does not exist. Creating one..."
    sp=$(az ad sp create-for-rbac --name "http://$spName")
else
    echo "Service principal exists. Resetting credentials..."
    # Use the application (client) ID with the --id parameter to reset credentials
    sp=$(az ad sp credential reset --id $spAppId)
fi



# Extract service principal details
clientId=$(echo $sp | jq -r '.appId')
clientSecret=$(echo $sp | jq -r '.password')
tenantId=$(echo $sp | jq -r '.tenant')

serviceBusEndpoint="${serviceBusNamespaceName}.servicebus.windows.net/"

# Define the scope for the role assignment
scope="/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.ServiceBus/namespaces/$serviceBusNamespaceName/queues/$queueName"

# Azure Service Bus Data Receiver role ID
serviceBusDataReceiverRoleId="4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0"

# Assign the role to the service principal with the correct scope
echo "Assigning Azure Service Bus Data Receiver role to the service principal..."
az role assignment create --assignee $clientId --role $serviceBusDataReceiverRoleId --scope $scope



# Write the service principal details to local.settings.json
cat > local.settings.json << EOF
{
    "IsEncrypted": false,
    "Values": {
        "AzureWebJobsStorage": "UseDevelopmentStorage=true",
        "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
        "AZURE_CLIENT_ID": "$clientId",
        "AZURE_CLIENT_SECRET": "$clientSecret",
        "AZURE_TENANT_ID": "$tenantId",
        "ServiceBusConnection__fullyQualifiedNamespace": "$serviceBusEndpoint",
        "ServiceBusMqttMessageQueueName": "$queueName"
    }
}
EOF

echo "local.settings.json has been created for local development."