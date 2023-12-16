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

# Deploy Bicep file
bicepFile="DeployCloudResources.bicep"
az deployment group create --name "${BaseName}Deployment" --resource-group $rgName --template-file $bicepFile --parameters baseName=$BaseName location=$Location