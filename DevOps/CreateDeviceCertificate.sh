#!/bin/bash

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
    echo "Not logged in to Azure. Please login using 'az login'."
    exit 1
fi

# Default values
deviceName="defaultDevice"
baseName=""

# Parse options
while getopts "d:b:" opt; do
    case $opt in
        d) deviceName=$OPTARG;;
        b) baseName=$OPTARG;;
        \?) echo "Invalid option -$OPTARG" >&2; exit 1;;
    esac
done

# Check for required base name
if [ -z "$baseName" ]; then
    echo "Base name (-b) is required."
    exit 1
fi
# Function to check if openssl is installed
check_openssl() {
    if ! command -v openssl &> /dev/null; then
        echo "OpenSSL not found. Installing OpenSSL..."
        sudo apt-get update && sudo apt-get install openssl
    fi
}


keyVaultName="${baseName}keyVault"

# Check for OpenSSL
check_openssl

# Root Certificate (50 years)
rootCAName="rootCA"
openssl genrsa -out "${rootCAName}.key" 2048
openssl req -x509 -new -nodes -key "${rootCAName}.key" -sha256 -days 18250 -out "${rootCAName}.pem"

# Device Certificate
deviceCertName="${deviceName}Cert"
openssl genrsa -out "${deviceCertName}.key" 2048
openssl req -new -key "${deviceCertName}.key" -out "${deviceCertName}.csr"
openssl x509 -req -in "${deviceCertName}.csr" -CA "${rootCAName}.pem" -CAkey "${rootCAName}.key" -CAcreateserial -out "${deviceCertName}.crt" -days 3650

# Check if root certificate exists in Key Vault
if ! az keyvault certificate show --vault-name $keyVaultName --name $rootCAName &> /dev/null; then
    # Upload root certificate to Key Vault
    az keyvault certificate import --vault-name $keyVaultName --name $rootCAName --file "${rootCAName}.pem"
fi

# Output device certificate
echo "Device Certificate for $deviceName:"
cat "${deviceCertName}.crt"

# Clean up
rm "${rootCAName}.key" "${rootCAName}.pem" "${deviceCertName}.key" "${deviceCertName}.csr" "${deviceCertName}.crt"
