#!/bin/bash
set -e

# Tillåt automatisk installation av CLI-tillägg utan interaktiva frågor
az config set extension.use_dynamic_install=yes_without_prompt

# Variabler
RG="rg-novatrix-v34"
LOCATION="swedencentral"
VNET="vnet-novatrix"
VM_NAME="vm-novatrix-web"
ADMIN_USER="azureuser"
VM_SIZE="Standard_B2ats_v2"

echo "1. Skapar Resursgrupp..."
az group create --name "$RG" --location "$LOCATION" -o table

echo "2. Skapar VNet och Subnät..."
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

az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name AzureBastionSubnet \
  --address-prefixes 10.0.3.0/26 \
  -o table

echo "3. Skapar Nätverkssäkerhetsgrupper (NSG)..."
az network nsg create --resource-group "$RG" --name nsg-web -o table
az network nsg create --resource-group "$RG" --name nsg-db -o table

# Koppla NSG till subnät
az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" --name snet-web --network-security-group nsg-web -o table
az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" --name snet-db --network-security-group nsg-db -o table

echo "4. Skapar NSG-regler..."
# Webbsubnät: Tillåt HTTP från Internet
az network nsg rule create \
  --resource-group "$RG" --nsg-name nsg-web --name Allow-HTTP-All \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "*" --destination-port-ranges 80 \
  -o table

# Webbsubnät: Tillåt SSH enbart från Azure Bastion Subnät
az network nsg rule create \
  --resource-group "$RG" --nsg-name nsg-web --name Allow-SSH-From-Bastion \
  --priority 110 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "10.0.3.0/26" --destination-port-ranges 22 \
  -o table

# Databassubnät: Tillåt DB-trafik enbart från snet-web
az network nsg rule create \
  --resource-group "$RG" --nsg-name nsg-db --name Allow-DB-From-Web \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "10.0.1.0/24" --destination-port-ranges 3306 1433 \
  -o table

echo "5. Skapar Public IP och Azure Bastion Standard (Detta tar ca 8-10 minuter)..."
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

echo "6. Skapar Virtuell Maskin (Webbserver utan NIC-NSG)..."
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
  --custom-data cloud-init.yaml \
  -o table

echo "Driftsättning klar! Bastion och Webbserver är konfigurerade."