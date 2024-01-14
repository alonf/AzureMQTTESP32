#!/bin/bash

# Check if logged in to Azure
if ! az account show > /dev/null 2>&1; then
    echo -e "\033[0;31mNot logged in to Azure. Please login using 'az login'.\033[0m"
    exit 1
fi

# Function to check if a resource group exists
check_resource_group_exists() {
    local rg=$1
    if az group exists --name "$rg"; then
        echo "Resource Group $rg exists."
    else
        echo -e "\033[0;31mResource Group $rg does not exist. Please create it or use a different Resource Group.\033[0m"
        exit 1
    fi
}


# Default values
rootCAName="rootCA"
intermidiateCAName="intermidiateCA"
clientName=""
baseName=""
subject="/C=IL/ST=Haifa/L=Binyamina/O=Fliess/OU=Home/emailAddress=alon@fliess.org"
defaultCN="fliess.org"
days=2000 #about 5 years
clientType=""


subscriptionId=$(az account show --query id -o tsv)

# Parse options
while getopts "d:b:t:" opt; do
    case $opt in
        d) clientName=$OPTARG;;
        b) baseName=$OPTARG;;
        t) clientType=$OPTARG;; # 'device' or 'cloud'
        \?) echo -e "\033[0;31mInvalid option -$OPTARG\033[0m" >&2; exit 1;;
    esac
done

# Check for required base name
if [ -z "$baseName" ]; then
    echo -e "\033[0;31mBase name (-b) is required.\033[0m"
    exit 1
fi
# Function to check if openssl is installed


# Ask the user for the client type if not provided as an argument
if [ -z "$clientType" ]; then
    echo -n "Please enter the client type ('device' or 'cloud'): "
    read clientType
fi

# Verify client type
if [[ "$clientType" != "device" && "$clientType" != "cloud" ]]; then
    echo -e "\033[0;31mInvalid client type. Use 'device' or 'cloud'.\033[0m"
    exit 1
fi

if [ -z "$clientName" ]; then
    echo -n "Please enter the client name: "
    read clientNameInput

    # Check if input is empty
    if [ -z "$clientNameInput" ]; then
        echo -e "\033[0;31mClient name is required.\033[0m"
        exit 1
    else
        clientName=$clientNameInput
    fi
fi

rgName="${baseName}rg"
namespaceName="${baseName}ns"

check_resource_group_exists "$rgName"

check_openssl() {
    if ! command -v openssl &> /dev/null; then
        echo -e "\033[0;31mOpenSSL not found. Installing OpenSSL...\033[0m"
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
deviceCertName="${clientName}Cert"  
openssl genrsa -out "${deviceCertName}.key" 4096  
openssl req -new -key "${deviceCertName}.key" -out "${deviceCertName}.csr" -subj $subject$"/CN=$clientName"  
openssl x509 -req -in "${deviceCertName}.csr" -CA "${intermidiateCAName}.pem" -CAkey "${intermidiateCAName}.key" -CAcreateserial -out "${deviceCertName}.pem" -days $days -sha256  
fingerprint=$(openssl x509 -in "${deviceCertName}.pem" -noout -fingerprint | sed 's/://g' | tr -d '[:space:]')

# Output device certificate
echo -e "\033[0;34mDevice fingerprint for $clientName: $fingerprint\033[0m"

#echo device certificate file names
echo -e "\033[0;36mDevice certificate files: ${deviceCertName}.key, ${deviceCertName}.csr and ${deviceCertName}.pem\033[0m"

# Retrieve and save the broker's certificate
openssl s_client -showcerts -connect ${baseName}ns.uaenorth-1.ts.eventgrid.azure.net:8883 </dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > brokerCert.pem

# Check if the broker certificate was successfully created
if [ -f "brokerCert.pem" ]; then
    echo -e "\033[0;34mBroker certificate successfully retrieved and saved as brokerCert.pem\033[0m"
else
    echo -e "\033[0;31mFailed to retrieve the broker certificate\033[0m"
    exit 1
fi


# Create the client in Azure Event Grid Namespace
if [ "$clientType" = "device" ] || [ "$clientType" = "cloud" ]; then
    clientAttributes="{\"type\": \"$clientType\"}"

    resourceId="/subscriptions/${subscriptionId}/resourceGroups/${rgName}/providers/Microsoft.EventGrid/namespaces/${namespaceName}/clients/${clientName}"

    az resource create --resource-type Microsoft.EventGrid/namespaces/clients \
        --id "$resourceId" \
        --api-version 2023-06-01-preview \
        --properties "{\"authenticationName\":\"${fingerprint}\", \"clientCertificateAuthentication\": {\"validationScheme\": \"ThumbprintMatch\", \"allowedThumbprints\": [\"${fingerprint//SHA1Fingerprint=}\"]}, \"attributes\":${clientAttributes}}"

    echo -e "\033[0;34mClient $clientName registered as $clientType type with fingerprint $fingerprint\033[0m"
else
    echo -e "\033[0;31mInvalid client type specified. Use 'device' or 'cloud'.\033[0m"
    exit 1
fi
