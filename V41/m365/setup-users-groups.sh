#!/bin/bash
# Automationsskript i Bash för Nordvik M365 IAM (Idempotent)
set -e

# Förhindrar att Git Bash konverterar Azure Graph-sökvägar
export MSYS_NO_PATHCONV=1

echo "=== Startar skapande av grupper och användare för Nordvik ==="

# 1. Hämta aktiv .onmicrosoft.com-domän automatiskt från Entra ID
TENANT_DOMAIN=$(az rest --method get --uri "https://graph.microsoft.com/v1.0/domains" --query "value[?isDefault].id" -o tsv)

if [ -z "$TENANT_DOMAIN" ]; then
    echo "Kunde inte hämta domän automatiskt." >&2
    read -p "Ange din tenant-domän manuellt (t.ex. org.onmicrosoft.com): " TENANT_DOMAIN
else
    echo "Hittade aktiv domän: $TENANT_DOMAIN"
fi

# 2. Be om lösenord för alla nya användare
read -sp "Ange tillfälligt lösenord för de nya användarna: " DEFAULT_PASSWORD
echo ""

# 3. Hjälpfunktion för säker grupphantering
create_group_if_not_exists() {
    local name="$1"
    local nickname="$2"
    local group_id=$(az ad group show --group "$name" --query id -o tsv 2>/dev/null || true)
    
    if [ -z "$group_id" ]; then
        echo "Skapar grupp: $name..." >&2
        group_id=$(az ad group create --display-name "$name" --mail-nickname "$nickname" --query id -o tsv)
    else
        echo "Gruppen $name finns redan (ID: $group_id)..." >&2
    fi
    echo "$group_id"
}

FORVALTARE_GROUP_ID=$(create_group_if_not_exists "grp-nordvik-forvaltare" "grp-nordvik-forvaltare")
EKONOMI_GROUP_ID=$(create_group_if_not_exists "grp-nordvik-ekonomi" "grp-nordvik-ekonomi")

# Hjälpfunktion för att tvätta namn till UPN
clean_upn() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/å/a/g; s/ä/a/g; s/ö/o/g; s/[^a-z0-9]/./g'
}

# Hjälpfunktion för idempotent användarhantering
get_or_create_user() {
    local name="$1"
    local upn="$2"
    local password="$3"

    local user_id=$(az ad user show --id "$upn" --query id -o tsv 2>/dev/null || true)

    if [ -z "$user_id" ]; then
        echo "Skapar ny användare: $name ($upn)..." >&2
        user_id=$(az ad user create \
            --display-name "$name" \
            --user-principal-name "$upn" \
            --password "$password" \
            --force-change-password-next-sign-in true \
            --query id -o tsv)
    else
        echo "Användaren finns redan, återanvänder ID ($upn)..." >&2
    fi
    echo "$user_id"
}

# Listor med användare
FORVALTARE_USERS=(
    "Anna Berg"
    "Björn Carlsson"
    "Cecilia Danielsson"
    "David Eriksson"
    "Elin Andersson"
)

EKONOMI_USERS=(
    "Albin Gunnarsson"
    "Gustav Hansson"
    "Helena Isaksson"
    "Ida Johansson"
    "Johan Persson"
)

# 4. Hantera förvaltare och koppla till grp-nordvik-forvaltare
echo -e "\nHanterar förvaltaranvändare..."
for name in "${FORVALTARE_USERS[@]}"; do
    safe_prefix=$(clean_upn "$name")
    upn="${safe_prefix}@${TENANT_DOMAIN}"

    user_id=$(get_or_create_user "$name" "$upn" "$DEFAULT_PASSWORD")

    az ad group member add --group "$FORVALTARE_GROUP_ID" --member-id "$user_id" 2>/dev/null || true
    echo "Kopplad: $name ($upn)"
done

# 5. Hantera ekonomianvändare och koppla till grp-nordvik-ekonomi
echo -e "\nHanterar ekonomianvändare..."
for name in "${EKONOMI_USERS[@]}"; do
    safe_prefix=$(clean_upn "$name")
    upn="${safe_prefix}@${TENANT_DOMAIN}"

    user_id=$(get_or_create_user "$name" "$upn" "$DEFAULT_PASSWORD")

    az ad group member add --group "$EKONOMI_GROUP_ID" --member-id "$user_id" 2>/dev/null || true
    echo "Kopplad: $name ($upn)"
done

HYRESGAST_GROUP_ID=$(create_group_if_not_exists "grp-nordvik-hyresgast" "grp-nordvik-hyresgast")
 
HYRESGAST_USERS=(
    "Hilda Lindqvist"
    "Hugo Lindqvist"
)
 
echo -e "\nHanterar hyresgästanvändare..."
for name in "${HYRESGAST_USERS[@]}"; do
    safe_prefix=$(clean_upn "$name")
    upn="${safe_prefix}@${TENANT_DOMAIN}"
 
    user_id=$(get_or_create_user "$name" "$upn" "$DEFAULT_PASSWORD")
 
    az ad group member add --group "$HYRESGAST_GROUP_ID" --member-id "$user_id" 2>/dev/null || true
    echo "Kopplad: $name ($upn)"
done
 

echo -e "\n=== Klar! Alla användare och grupper har skapats och kopplats ==="