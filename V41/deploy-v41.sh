#!/bin/bash
# Bygger upp hela Nordvik-miljön från noll. Kör från projektmappen: bash deploy-v41.sh
# Förutsättning: kör m365/setup-users-groups.sh först så att grupperna och användarna finns.
set -e
export MSYS_NO_PATHCONV=1

RG="rg-nordvik"
LOCATION="swedencentral"
NAMN_SUFFIX="02albper"
LOPNUMMER="01"
APP_NAME="app-nordvik-portal"
FUNC_NAME="func-nordvik-backend-${NAMN_SUFFIX}${LOPNUMMER}"
ARM_TEMPLATE="arm/azuredeploy-nordvik.json"
ARM_PARAMS="arm/azuredeploy-nordvik.parameters.local.json"
BACKEND_DIR="backend"   # mappen med function_app.py, host.json, requirements.txt
WEB_LOCATION="northeurope"         # lämna tom. Sätt t.ex. "northeurope" om swedencentral saknar kapacitet för Container Apps

echo "=== 1/6 Registrerar resursleverantörer (ofarligt om redan gjort) ==="
for ns in Microsoft.Web Microsoft.Storage Microsoft.Network Microsoft.Authorization Microsoft.App Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" -o none
done

echo "=== 2/6 Skapar resursgrupp ==="
az group create --name "$RG" --location "$LOCATION" -o none

echo "=== 3/6 Skapar app-registrering för inloggning (hoppas över om den finns) ==="
CLIENT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$CLIENT_ID" ]; then
  CLIENT_ID=$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
  echo "Skapade app-registrering: $CLIENT_ID"
else
  echo "Återanvänder app-registrering: $CLIENT_ID"
fi
APP_OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)
# Tjänstobjektet behövs för att användare ska kunna logga in (finns det redan ger kommandot ett ofarligt fel)
az ad sp create --id "$CLIENT_ID" -o none 2>/dev/null || true

echo "=== 4/6 Deployar infrastrukturen (ARM) ==="
FORV_ID=$(az ad group show --group grp-nordvik-forvaltare --query id -o tsv 2>/dev/null || true)
EKON_ID=$(az ad group show --group grp-nordvik-ekonomi --query id -o tsv 2>/dev/null || true)
[ -z "$FORV_ID" ] && echo "Obs: gruppen grp-nordvik-forvaltare hittades inte, hoppar över dess behörigheter"
[ -z "$EKON_ID" ] && echo "Obs: gruppen grp-nordvik-ekonomi hittades inte, hoppar över dess behörigheter"

MY_IP=$(curl -s --max-time 5 https://api.ipify.org || true)
echo "Din publika IP: ${MY_IP:-okänd}"

EXTRA=()
[ -n "$WEB_LOCATION" ] && EXTRA+=(webbPlats="$WEB_LOCATION")

az deployment group create \
  --resource-group "$RG" \
  --template-file "$ARM_TEMPLATE" \
  --parameters "$ARM_PARAMS" \
  --parameters namnSuffix="$NAMN_SUFFIX" lopnummer="$LOPNUMMER" entraClientId="$CLIENT_ID" \
               forvaltareGruppId="$FORV_ID" ekonomiGruppId="$EKON_ID" klientIp="$MY_IP" \
               "${EXTRA[@]}" \
  -o none

echo "=== 5/6 Registrerar webbplatsens adress som inloggningsadress ==="
WEB_URL=$(az deployment group show --resource-group "$RG" --name "$(basename "$ARM_TEMPLATE" .json)" \
  --query "properties.outputs.webUrl.value" -o tsv)
echo "Webbadress: $WEB_URL"
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{\"spa\":{\"redirectUris\":[\"$WEB_URL\",\"$WEB_URL/\"]}}"

echo "=== 6/6 Publicerar function app-koden (rolltilldelningar kan behöva några minuter) ==="
sleep 60
for attempt in 1 2 3; do
  if (cd "$BACKEND_DIR" && func azure functionapp publish "$FUNC_NAME" --python); then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    echo "Publiceringen misslyckades 3 gånger. Vänta några minuter och kör kommandot manuellt." >&2
    exit 1
  fi
  echo "Försök $attempt misslyckades, väntar 60 sekunder och försöker igen..."
  sleep 60
done

echo ""
echo "=== Klar! ==="
echo "Webb:    $WEB_URL"
echo "Backend: https://$FUNC_NAME.azurewebsites.net/api"