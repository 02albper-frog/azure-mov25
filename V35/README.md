# Azure – Uppgift 2

**Namn:** Albin Persson
**Kurs:** Azure v.35

## Delmoment 1 – Repo

Skapade V35-mappen i repot och uppdaterade huvud-README med länk till denna dokumentation.

**Verifiering:** Mappen och länken syns korrekt på GitHub.

## Delmoment 2 – Skapa identiteter

Jag skapade användare och säkerhetsgrupper i Entra ID för att representera Novatrix olika roller.

**Skapa användare:** Gå till Användare, klicka "Ny användare" → välj "Skapa ny användare" → ange användarnamn och visningsnamn (t.ex. Lena Drift) → sätt ett lösenord (eller låt Azure generera ett) → klicka "Granska + skapa", och sedan "Skapa".

**Skapa grupper:** Gå till Grupper, klicka "Ny grupp" → grupptyp: Säkerhet (inte Microsoft 365) → ange gruppnamn → klicka "Skapa".

Jag skapade följande användare och grupper:

| Typ | Namn | Roll |
|---|---|---|
| Användare | David | Utvecklare |
| Användare | Lena | Drift |
| Grupp | Azure-Dev | Utvecklingsteam |
| Grupp | Azure-Drift | Driftteam |

David lades till i gruppen Azure-Dev och Lena i gruppen Azure-Drift.

**Verifiering:** Användarna och grupperna syns i Entra ID, med rätt medlemskap.

![alt text](Azure-groups.png)

![alt text](Azure-Users.png)
## Delmoment 3 – Tilldela behörigheter (RBAC)

Jag satte behörigheterna på resursgruppsnivå under Access Control (IAM), så att de bara gäller där, inte på hela prenumerationen. Jag tilldelade rollen **Reader** till gruppen Azure-Dev och rollen **Contributor** till gruppen Azure-Drift.

**Motivering (least privilege):**

| Grupp | Roll | Motivering |
|---|---|---|
| Azure-Dev | Reader | Utvecklare behöver kunna se resurser och konfiguration för felsökning, men inte ändra något i miljön. |
| Azure-Drift | Contributor | Driftteamet behöver kunna skapa, ändra och hantera resurser i den dagliga driften, men får inte hantera behörigheter eller åtkomst (det kräver Owner, som ingen av grupperna har). |

**Verifiering:** Rolltilldelningarna syns under Access Control (IAM) på resursgruppen.

![alt text](Tilldelningar-DEV.png) ![alt text](Tilldelningar-DRIFT.png)

## Delmoment 4 – Förbered en identitet för appen

Jag skapade en **user-assigned managed identity**, `id-novatrix-app`, som applikationen senare (v37) ska använda för att nå lagringen utan lösenord i koden.

```bash
az identity create --name id-novatrix-app --resource-group rg-novatrix-v34
```

Jag sparade `clientId` och `principalId` från utskriften, så att jag senare kan koppla identiteten och ge den behörighet till storage-kontot i v37. Identiteten har medvetet inga behörigheter ännu.

**Verifiering:** Identiteten syns i resursgruppen `rg-novatrix-v34`. Jag kontrollerade även att den saknar rolltilldelningar med:

```bash
az role assignment list --assignee <principalId> -o table
```

vilket gav en tom lista, precis som förväntat.

![alt text](Managed-identity.png)

## Delmoment 5 – Verifiera och dokumentera

