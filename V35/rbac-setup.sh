#!/bin/bash
# Skärper least privilege-modellen för Novatrix (v35 VG)
set -e

# Förhindrar att Git Bash (MINGW64) konverterar /subscriptions/ till en Windows-sökväg
export MSYS_NO_PATHCONV=1

SUBSCRIPTION_ID="<YOUR_SUBSCRIPTION_ID>"
RESOURCE_GROUP="rg-novatrix-v34"
SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

echo "Sätter aktiv prenumeration..."
az account set --subscription "$SUBSCRIPTION_ID"

create_group_if_not_exists() {
    local name="$1"
    local nickname="$2"
    if ! az ad group show --group "$name" &>/dev/null; then
        echo "Skapar grupp: $name..."
        az ad group create --display-name "$name" --mail-nickname "$nickname" > /dev/null
    else
        echo "Gruppen $name finns redan, hoppar över..."
    fi
}

create_group_if_not_exists "Azure-Security" "azure-security"
create_group_if_not_exists "Azure-Admin" "azure-admin"
create_group_if_not_exists "Azure-Support" "azure-support"

echo "Väntar 10 sekunder på att Entra ID ska replikera nya grupper..."
sleep 10

echo "Hämtar objectId för samtliga grupper..."
DEV_ID=$(az ad group show --group "Azure-Dev" --query id -o tsv)
DRIFT_ID=$(az ad group show --group "Azure-Drift" --query id -o tsv)
SECURITY_ID=$(az ad group show --group "Azure-Security" --query id -o tsv)
ADMIN_ID=$(az ad group show --group "Azure-Admin" --query id -o tsv)
SUPPORT_ID=$(az ad group show --group "Azure-Support" --query id -o tsv)

echo "Tilldelar roller enligt least privilege..."
az role assignment create --assignee-object-id "$DEV_ID" --assignee-principal-type Group --role "Reader" --scope "$SCOPE"
az role assignment create --assignee-object-id "$DRIFT_ID" --assignee-principal-type Group --role "Contributor" --scope "$SCOPE"
az role assignment create --assignee-object-id "$SECURITY_ID" --assignee-principal-type Group --role "Security Admin" --scope "$SCOPE"
az role assignment create --assignee-object-id "$ADMIN_ID" --assignee-principal-type Group --role "Owner" --scope "$SCOPE"
az role assignment create --assignee-object-id "$SUPPORT_ID" --assignee-principal-type Group --role "Virtual Machine Contributor" --scope "$SCOPE"

echo "Klart! Verifierar samtliga tilldelningar:"
az role assignment list --scope "$SCOPE" -o table