#!/bin/bash

# Check if logged in to Azure
az account show > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Not logged in to Azure. Please login using 'az login'."
    exit 1
fi

# Default location
defaultLocation="uaenorth"

# Check for base name argument
if [ -z "$1" ]; then
    echo "Usage: $0 <BaseName> [Location]"
    exit 1
fi

# Assign arguments
BaseName=$1
Location=${2:-$defaultLocation}

# Create resource group
rgName="${BaseName}rg"
az group create --name $rgName --location $Location

userObjectId=$(az ad signed-in-user show --query id -o tsv)
if [ -z "$userObjectId" ]; then
    echo "Failed to get the logged-in user's object ID."
    exit 1
fi

# Deploy Bicep file
bicepFile="DeployCloudResources.bicep"
updateBicepFile="SetEventGridNamespaceRouting.bicep"

az deployment group create --name "${BaseName}Deployment" --resource-group $rgName --template-file $bicepFile --parameters baseName=$BaseName location=$Location userObjectId=$userObjectId

# Now that we have manage identity for the namesapce, we can add the message routing
az deployment group create --name "Update${BaseName}Deployment" --resource-group $rgName --template-file $updateBicepFile --parameters baseName=$BaseName location=$Location 
