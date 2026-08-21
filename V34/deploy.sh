#!/bin/bash
# Automatiserad provisionering av Novatrix kundtjänstmiljö
# Kör från repots v34/-mapp: bash deploy.sh

set -e

RESOURCE_GROUP="rg-novatrix-v34"
LOCATION="swedencentral"
VM_NAME="vm-novatrix-web"
VM_SIZE="Standard_B2ats_v2"

echo "Skapar resursgrupp..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

echo "Skapar virtuell maskin med cloud-init..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --image Ubuntu2204 \
  --size "$VM_SIZE" \
  --admin-username azureuser \
  --generate-ssh-keys \
  --custom-data cloud-init.yaml \
  --public-ip-sku Standard

echo "Öppnar port 80 för HTTP..."
az vm open-port \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --port 80 \
  --priority 900

echo "Klart! Publik IP:"
az vm show -d \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --query publicIps -o tsv
