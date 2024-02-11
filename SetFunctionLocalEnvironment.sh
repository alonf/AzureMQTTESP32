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

# Define the topic name
topicName="telemetry"

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
spExists=$(az ad sp list --display-name $spName --query "[].appId" -o tsv)

if [ -z "$spExists" ]; then
    # Service principal does not exist, create it
    echo "Service principal does not exist. Creating one..."
    sp=$(az ad sp create-for-rbac --name http://$spName --skip-assignment)
else
    # Service principal exists, reset its credentials
    echo "Service principal exists. Resetting credentials..."
    sp=$(az ad sp credential reset --name http://$spName)
fi

# Extract service principal details
clientId=$(echo $sp | jq -r '.appId')
clientSecret=$(echo $sp | jq -r '.password')
tenantId=$(echo $sp | jq -r '.tenant')


# Define the scope for the role assignment
scope="/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.EventGrid/topics/$topicName"

# Role definition ID for EventGrid Data Sender
roleDefinitionId="7b7c9e37-2087-4ee1-8a0b-20e5c7d9c6d2"

# Assign the role to the service principal
echo "Assigning EventGrid Data Sender role to the service principal..."
az role assignment create --assignee $clientId --role $roleDefinitionId --scope $scope


# Write the service principal details to local.settings.json
cat > local.settings.json << EOF
{
    "IsEncrypted": false,
    "Values": {
        "AzureWebJobsStorage": "UseDevelopmentStorage=true",
        "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
        "AZURE_CLIENT_ID": "$clientId",
        "AZURE_CLIENT_SECRET": "$clientSecret",
        "AZURE_TENANT_ID": "$tenantId"
    }
}
EOF

echo "Service principal setup complete."
