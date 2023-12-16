#!/bin/bash

# Variables
resourceGroupName="eps32rg"
location="uaenorth"
eventGridTopicName="mqttesp32events"
clientGroupName="esp32ClinetGroup"
functionAppName="ESP32CloudControllerApp"
functionName="MQTTHandler"
namespaceName="esp32Namespace"

# Check if logged in to Azure
az account show > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Not logged in to Azure. Please login using 'az login'."
    exit 1
fi

# Get the current Azure subscription ID
subscriptionId=$(az account show --query id --output tsv)
echo "Using Azure Subscription ID: $subscriptionId"

# Create a resource group if it doesn't exist
groupExists=$(az group exists --name $resourceGroupName)
if [ "$groupExists" = "false" ]; then
    az group create --name $resourceGroupName --location $location
fi

# Create an Event Grid namespace if it doesn't exist
namespaceExists=$(az eventgrid namespace exists --name $namespaceName --resource-group $resourceGroupName)
if [ "$namespaceExists" = "false" ]; then
    az eventgrid namespace create --name $namespaceName --location $location --resource-group $resourceGroupName
fi

# Create an Event Grid topic within the namespace if it doesn't exist
topicExists=$(az eventgrid topic exists --name $eventGridTopicName --resource-group $resourceGroupName --namespace-name $namespaceName)
if [ "$topicExists" = "false" ]; then
    az eventgrid topic create --name $eventGridTopicName --location $location --resource-group $resourceGroupName --namespace-name $namespaceName
fi

# Create a client group with query
az eventgrid partner topic create --name $eventGridTopicName --resource-group $resourceGroupName --name $clientGroupName --query "attributes.type='esp32'"

# Create two topic spaces
az eventgrid topic-space create --name "Device2Cloud" --topic-name $eventGridTopicName --resource-group $resourceGroupName --template "device/+/twin/reported" "device/+/telemetry" "device/+/responses"
az eventgrid topic-space create --name "Cloud2Device" --topic-name $eventGridTopicName --resource-group $resourceGroupName --template "device/+/twin/desired" "device/+/commands" "device/+/responses"

# Create Permission Bindings
az eventgrid permission create --name "Device2CloudPublisher" --client-group-name $clientGroupName --topic-space-name "Device2Cloud" --permission-type Publisher
az eventgrid permission create --name "Device2CloudSubscriber" --client-group-name $clientGroupName --topic-space-name "Device2Cloud" --permission-type Subscriber
az eventgrid permission create --name "Cloud2DevicePublisher" --client-group-name $clientGroupName --topic-space-name "Cloud2Device" --permission-type Publisher
az eventgrid permission create --name "Cloud2DeviceSubscriber" --client-group-name $clientGroupName --topic-space-name "Cloud2Device" --permission-type Subscriber


# Link Azure Function to Event Grid topic as a subscription if it doesn't exist
subscriptionExists=$(az eventgrid event-subscription exists --name "<YourSubscriptionName>" --source-resource-id $(az eventgrid topic show --name $eventGridTopicName --namespace-name $namespaceName --resource-group $resourceGroupName --query id --output tsv))
if [ "$subscriptionExists" = "false" ]; then
    functionAppId=$(az functionapp show --name $functionAppName --resource-group $resourceGroupName --query id --output tsv)
    az eventgrid event-subscription create --source-resource-id $(az eventgrid topic show --name $eventGridTopicName --namespace-name $namespaceName --resource-group $resourceGroupName --query id --output tsv) --name "<YourSubscriptionName>" --endpoint-type azurefunction --endpoint $functionAppId/functions/$functionName
fi