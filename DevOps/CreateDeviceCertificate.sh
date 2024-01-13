#!/bin/bash

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
    echo "Not logged in to Azure. Please login using 'az login'."
    exit 1
fi

# Default values
rootCAName="rootCA"
intermidiateCAName="intermidiateCA"
deviceName="defaultDevice"
baseName=""
subject="/C=IL/ST=Haifa/L=Binyamina/O=Fliess/OU=Home/emailAddress=alon@fliess.org"
defaultCN="fliess.org"
days=20000

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

# Check if root certificate exists in Key Vault as a secret
if ! az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}PemSecret" &> /dev/null || \
   ! az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}KeySecret" &> /dev/null; then

    # Create root CA certificate and key
    openssl genrsa -out "${rootCAName}.key" 4096
    openssl req -x509 -new -nodes -key ${rootCAName}.key -sha256 -days $days -out ${rootCAName}.pem -subj $subject$"/CN=$defaultCN"

    # Store root CA certificate
    rootCAPemContent=$(cat "${rootCAName}.pem" | base64 -w0)
    az keyvault secret set --vault-name $keyVaultName --name "${rootCAName}PemSecret" --value "$rootCAPemContent"

    # Store root CA private key
    rootCAKeyContent=$(cat "${rootCAName}.key" | base64 -w0)
    az keyvault secret set --vault-name $keyVaultName --name "${rootCAName}KeySecret" --value "$rootCAKeyContent"

else
    # Download and decode the root CA certificate
    rootCAPemContent=$(az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}PemSecret" --query "value" -o tsv | base64 --decode)
    echo "$rootCAPemContent"  > "${rootCAName}.pem"

    # Download and decode the root CA private key
    rootCAKeyContent=$(az keyvault secret show --vault-name $keyVaultName --name "${rootCAName}KeySecret" --query "value" -o tsv | base64 --decode)
    echo "$rootCAKeyContent" > "${rootCAName}.key"
fi

# Check if intermidiate certificate exists in Key Vault as a secret
if ! az keyvault secret show --vault-name $keyVaultName --name "${intermidiateCAName}PemSecret" &> /dev/null || \
   ! az keyvault secret show --vault-name $keyVaultName --name "${intermidiateCAName}KeySecret" &> /dev/null || \
   ! az keyvault secret show --vault-name $keyVaultName --name "${intermidiateCAName}CsrSecret" &> /dev/null; then

     # Create intermidiate CA certificate and key
     openssl genrsa -out "${intermidiateCAName}.key" 4096  
     openssl req -new -key "${intermidiateCAName}.key" -out "${intermidiateCAName}.csr" -subj $subject$"/CN=$intermidiateCAName"  
     openssl x509 -req -in "${intermidiateCAName}.csr" -CA "${rootCAName}.pem" -CAkey "${rootCAName}.key" -CAcreateserial -out "${intermidiateCAName}.pem" -days $days -sha256  

     # Store intermidiate CA certificate
     intermidiateCAPemContent=$(cat "${intermidiateCAName}.pem" | base64 -w0)
     az keyvault secret set --vault-name $keyVaultName --name "${intermidiateCAName}PemSecret" --value "$intermidiateCAPemContent"
     
     # Store intermidiate CA private key
     intermidiateCAKeyContent=$(cat "${intermidiateCAName}.key" | base64 -w0)
     az keyvault secret set --vault-name $keyVaultName --name "${intermidiateCAName}KeySecret" --value "$intermidiateCAKeyContent"
     
     # Store intermidiate CA CSR
     intermidiateCACsrContent=$(cat "${intermidiateCAName}.csr" | base64 -w0)
     az keyvault secret set --vault-name $keyVaultName --name "${intermidiateCAName}CsrSecret" --value "$intermidiateCACsrContent"

else
    echo "Downloading intermidiate certificate"  
    # Download and decode the intermidiate CA certificate  
    intermidiateCAPemContent=$(az keyvault secret show --vault-name $keyVaultName --name "${intermidiateCAName}PemSecret" --query "value" -o tsv | base64 --decode)  
    echo "$intermidiateCAPemContent"  > "${intermidiateCAName}.pem"  
  
    # Download and decode the intermidiate CA private key  
    intermidiateCAKeyContent=$(az keyvault secret show --vault-name $keyVaultName --name "${intermidiateCAName}KeySecret" --query "value" -o tsv | base64 --decode)  
    echo "$intermidiateCAKeyContent" > "${intermidiateCAName}.key"  
  
    # Download and decode the intermidiate CA CSR  
    intermidiateCACsrContent=$(az keyvault secret show --vault-name $keyVaultName --name "${intermidiateCAName}CsrSecret" --query "value" -o tsv | base64 --decode)  
    echo "$intermidiateCACsrContent" > "${intermidiateCAName}.csr" 
fi


# Device Certificate
deviceCertName="${deviceName}Cert"  
openssl genrsa -out "${deviceCertName}.key" 4096  
openssl req -new -key "${deviceCertName}.key" -out "${deviceCertName}.csr" -subj $subject$"/CN=$deviceName"  
openssl x509 -req -in "${deviceCertName}.csr" -CA "${intermidiateCAName}.pem" -CAkey "${intermidiateCAName}.key" -CAcreateserial -out "${deviceCertName}.pem" -days $days -sha256  
fingerprint=$(openssl x509 -in "${deviceCertName}.pem" -noout -fingerprint | sed 's/://g' | tr -d '[:space:]')

# Output device certificate
echo -e "\033[0;34mDevice fingerprint for $deviceName: $fingerprint\033[0m"

#echo device certificate file names
echo -e "\033[0;36mDevice certificate files: ${deviceCertName}.key, ${deviceCertName}.csr and ${deviceCertName}.pem\033[0m"

