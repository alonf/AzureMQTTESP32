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

rootCAName="rootCA"

# Check if root certificate exists in Key Vault as a secret
if ! az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}CertSecret" &> /dev/null || \
   ! az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}KeySecret" &> /dev/null; then

     echo -e "\033[0;32mEnter information for the root certificate:\033[0m"

    # Create root CA certificate and key
    openssl genrsa -out "${rootCAName}.key" 2048
    openssl req -x509 -new -nodes -key "${rootCAName}.key" -sha256 -days 18250 -out "${rootCAName}.crt"

    # Store root CA certificate
    rootCACertContent=$(base64 "${rootCAName}.crt")
    az keyvault secret set --vault-name $keyVaultName --name "${rootCAName}CertSecret" --value "$rootCACertContent"

    # Store root CA private key
    rootCAKeyContent=$(base64 "${rootCAName}.key")
    az keyvault secret set --vault-name $keyVaultName --name "${rootCAName}KeySecret" --value "$rootCAKeyContent"
else
    echo "Downloading root certificate"
   # Download and decode the root CA certificate
    rootCACertContent=$(az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}CertSecret" --query "value" -o tsv)
    echo "$rootCACertContent" | base64 --decode > "${rootCAName}.crt"

    # Download and decode the root CA private key
    rootCAKeyContent=$(az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}KeySecret" --query "value" -o tsv)
    echo "$rootCAKeyContent" | base64 --decode > "${rootCAName}.key"
fi

echo -e "\033[0;32mEnter information for the device certificate:\033[0m"

# Device Certificate
deviceCertName="${deviceName}Cert"
openssl genrsa -out "${deviceCertName}.key" 2048
openssl req -new -key "${deviceCertName}.key" -out "${deviceCertName}.csr"
openssl x509 -req -in "${deviceCertName}.csr" -CA "${rootCAName}.crt" -CAkey "${rootCAName}.key" -CAcreateserial -out "${deviceCertName}.crt" -days 3650

# Output device certificate
echo -e "\033[0;34mDevice Certificate for $deviceName:\033[0m"

cat "${deviceCertName}.crt"

# Clean up
rm "${rootCAName}.*" 

cat "${deviceCertName}.crt" "${deviceCertName}.key" > "${deviceCertName}.pem"

#echo device certificate file names
echo -e "\033[0;36mDevice certificate files: ${deviceCertName}.key, ${deviceCertName}.crt and ${deviceCertName}.pem\033[0m"
