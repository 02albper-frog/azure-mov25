# azure-mov25

**Namn:** Albin Persson
**Kurs:** Microsoft Azure

## Vecka 34 – Compute och kom igång

Provisionerar en Ubuntu-VM i Azure, installerar Nginx och driftsätter en enkel kundtjänstsida med ärendeformulär för Novatrix AB.

Se [`V34/README.md`](./V34/README.md) för fullständig dokumentation.

## Vecka 35 – Identitet och behörigheter (IAM)

Implementerar en skalbar *least privilege*-modell för Novatrix AB i Entra ID. Innehåller skapande av användare, fem dedikerade säkerhetsgrupper, automatiserad rolltilldelning via Azure CLI (`rbac-setup.sh`) samt förberedelse av en hanterad identitet (Managed Identity).

Se [`V35/README.md`](./V35/README.md) för fullständig dokumentation.

## Vecka 36 – Nätverk och Defense in Depth

Etablerar ett säkert virtuellt nätverk (`vnet-novatrix`) uppdelat i ett publikt subnät (`snet-web`) för webbformuläret och ett isolerat subnät (`snet-db`) för backend och lagring. Tillämpar *Defense in Depth* med subnätskopplade NSG:er, strikta trafikregler samt begränsad administrativ SSH-åtkomst via IP-begränsning och Azure Bastion.

Se [`V36/README.md`](./V36/README.md) för fullständig dokumentation.

## Vecka 37 – Automatiserad Lagring & Sömlös Integration (IaC)

Fullbordar den automatiserade infrastrukturen för Novatrix AB genom att integrera Azure Blob Storage med en nyckellös User-Assigned Managed Identity (`id-novatrix-app`) på container-scope (*least privilege*). Hela miljöns livscykel styrs via Infrastructure as Code (`deploy-all-v37.sh` och `cloud-init`).

Se [`V37/README.md`](./V37/README.md) för fullständig dokumentation.
