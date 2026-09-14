#!/bin/bash
set -e

# Förhindra att Git Bash konverterar Azure-sökvägar på Windows
export MSYS_NO_PATHCONV=1

# Tillåt automatisk installation av CLI-tillägg utan interaktiva frågor
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors

# ==============================================================================
# VÄXLA BASTION HÄR: Ändra till "true" för att driftsätta Azure Bastion
# ==============================================================================
ENABLE_BASTION=true

# Variabler
RG="rg-novatrix-v34"
LOCATION="swedencentral"
VNET="vnet-novatrix"
VM_NAME="vm-novatrix-web"
ADMIN_USER="azureuser"
VM_SIZE="Standard_B2ats_v2"
STORAGE_ACCOUNT="stnovatrixv37albin"
CONTAINER_NAME="tickets"
IDENTITY_NAME="id-novatrix-app"

# Hämta din egen publika IP-adress automatiskt
MY_IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
echo "Identifierade din publika IP-adress: $MY_IP"

echo "1. Sanerar cloud-init-v37.yaml för Windows/ASCII-fel..."
sed -i 's/„/"/g; s/“/"/g; s/”/"/g; s/’/'\''/g; s/‘/'\''/g' cloud-init-v37.yaml
sed -i 's/\r$//' cloud-init-v37.yaml
iconv -c -f UTF-8 -t ASCII//TRANSLIT cloud-init-v37.yaml > cloud-init-v37.yaml.tmp && mv cloud-init-v37.yaml.tmp cloud-init-v37.yaml

echo "2. Rensar ev. gammal resursgrupp..."
az group delete --name "$RG" --yes || true

echo "3. Skapar Resursgrupp..."
az group create --name "$RG" --location "$LOCATION" -o table

echo "4. Skapar VNet och Subnät (snet-web, snet-db)..."
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name snet-web \
  --subnet-prefixes 10.0.1.0/24 \
  -o table

az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name snet-db \
  --address-prefixes 10.0.2.0/24 \
  -o table

if [ "$ENABLE_BASTION" = true ]; then
  echo "4b. Skapar AzureBastionSubnet..."
  az network vnet subnet create \
    --resource-group "$RG" \
    --vnet-name "$VNET" \
    --name AzureBastionSubnet \
    --address-prefixes 10.0.3.0/26 \
    -o table
fi

echo "5. Skapar Nätverkssäkerhetsgrupper (NSG)..."
az network nsg create --resource-group "$RG" --name nsg-web -o table
az network nsg create --resource-group "$RG" --name nsg-db -o table

# Koppla NSG till subnät
az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" --name snet-web --network-security-group nsg-web -o table
az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" --name snet-db --network-security-group nsg-db -o table

echo "6. Skapar NSG-regler..."
# Webbsubnät: Tillåt HTTP från hela Internet
az network nsg rule create \
  --resource-group "$RG" --nsg-name nsg-web --name Allow-HTTP-All \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "*" --destination-port-ranges 80 \
  -o table

# Webbsubnät: SSH-regel beroende på Bastion-inställning
if [ "$ENABLE_BASTION" = true ]; then
  echo "Konfigurerar SSH-regel: Tillåter enbart åtkomst från Azure Bastion (10.0.3.0/26)..."
  az network nsg rule create \
    --resource-group "$RG" --nsg-name nsg-web --name Allow-SSH-From-Bastion \
    --priority 110 --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes "10.0.3.0/26" --destination-port-ranges 22 \
    -o table
else
  echo "Konfigurerar SSH-regel: Tillåter enbart åtkomst från din IP ($MY_IP)..."
  az network nsg rule create \
    --resource-group "$RG" --nsg-name nsg-web --name Allow-SSH-MyIP \
    --priority 110 --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes "$MY_IP/32" --destination-port-ranges 22 \
    -o table
fi

# Databassubnät: Tillåt DB-trafik enbart från snet-web
az network nsg rule create \
  --resource-group "$RG" --nsg-name nsg-db --name Allow-DB-From-Web \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "10.0.1.0/24" --destination-port-ranges 3306 1433 \
  -o table

if [ "$ENABLE_BASTION" = true ]; then
  echo "6b. Skapar Azure Bastion Host och Public IP (Tar ca 8-10 minuter)..."
  az network public-ip create \
    --resource-group "$RG" --name pip-bastion \
    --sku Standard --allocation-method Static \
    -o table

  az network bastion create \
    --resource-group "$RG" \
    --name bastion-novatrix \
    --public-ip-address pip-bastion \
    --vnet-name "$VNET" \
    --sku Standard \
    --enable-tunneling \
    -o table
fi

echo "7. Skapar Lagringskonto och Blob-container..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  -o table

az storage container create \
  --account-name "$STORAGE_ACCOUNT" \
  --name "$CONTAINER_NAME" \
  --auth-mode login \
  -o table

echo "8. Skapar Managed Identity och tilldelar RBAC-roll..."
az identity create \
  --name "$IDENTITY_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  -o table

PRINCIPAL_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RG" --query principalId -o tsv)
IDENTITY_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RG" --query id -o tsv)
STORAGE_ID=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RG" --query id -o tsv)
CONTAINER_SCOPE="${STORAGE_ID}/blobServices/default/containers/${CONTAINER_NAME}"

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$CONTAINER_SCOPE" \
  -o table

echo "9. Skapar Virtuell Maskin (Webbserver utan NIC-NSG)..."
az vm create \
  --resource-group "$RG" \
  --name "$VM_NAME" \
  --image Ubuntu2204 \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --vnet-name "$VNET" \
  --subnet snet-web \
  --nsg "" \
  --public-ip-address pip-web \
  --assign-identity "$IDENTITY_ID" \
  --custom-data cloud-init-v37.yaml \
  -o table

PUBLIC_IP=$(az vm show --resource-group "$RG" --name "$VM_NAME" --show-details --query publicIps -o tsv)

echo "----------------------------------------------------"
echo "Driftsättning klar!"
echo "Bastion aktiverad: $ENABLE_BASTION"
if [ "$ENABLE_BASTION" = false ]; then
  echo "SSH är begränsat till din IP: $MY_IP"
else
  echo "SSH är begränsat till Bastion Subnet (10.0.3.0/26)"
fi
echo "Surfa till: http://$PUBLIC_IP"
echo "----------------------------------------------------"