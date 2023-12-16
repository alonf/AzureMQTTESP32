#!/bin/bash

# Function to check if openssl is installed
check_openssl() {
    if ! command -v openssl &> /dev/null; then
        echo "OpenSSL not found. Installing OpenSSL..."
        sudo apt-get update && sudo apt-get install openssl
    fi
}

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
    echo "Not logged in to Azure. Please login using 'az login'."
    exit 1
fi

# Get the current Azure subscription ID
subscriptionId=$(az account show --query id --output tsv)
echo "Using Azure Subscription ID: $subscriptionId"

# Check for OpenSSL
check_openssl

# Get parameters
deviceName=${1:-"defaultDevice"}
expiryYears=${2:-50}
rootExpiryDays=$((50 * 365)) # 50 years for the root certificate
deviceExpiryDays=$(($expiryYears * 365)) # Convert years to days

# Root Certificate (50 years)
rootCAName="rootCA"
openssl genrsa -out "${rootCAName}.key" 2048
openssl req -x509 -new -nodes -key "${rootCAName}.key" -sha256 -days $rootExpiryDays -out "${rootCAName}.pem"

# Device Certificate
deviceCertName="${deviceName}Cert"
openssl genrsa -out "${deviceCertName}.key" 2048
openssl req -new -key "${deviceCertName}.key" -out "${deviceCertName}.csr"
openssl x509 -req -in "${deviceCertName}.csr" -CA "${rootCAName}.pem" -CAkey "${rootCAName}.key" -CAcreateserial -out "${deviceCertName}.crt" -days $deviceExpiryDays -sha256

# Output device certificate
echo "Device Certificate for $deviceName:"
cat "${deviceCertName}.crt"
