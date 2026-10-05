# Azure – Uppgift 8 (v41)

**Namn:** Albin Persson  
**Kurs:** Azure v.41 (Examination)


[ Hyresgäst / Webbläsare ]
           │
           │ (HTTPS GET - Hämtar portalens UI)
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  vnet-nordvik (Virtual Network)                                 │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ snet-nordvik-app                                          │  │
│  │                                                           │  │
│  │  1. Container Web Portal (Frontend)                       │  │
│  │     - Körs i Container (t.ex. Azure Container Instance)   │  │
│  │     - Levererar formuläret & gränssnittet till hyresgäst  │  │
│  │                                                           │  │
│  │  2. func-nordvik-backend (Azure Function - Serverless)    │  │
│  │     - Hanterar POST (mottagning av felanmälan & bild)     │  │
│  │     - Managed Identity (System-Assigned)                  │  │
│  └───────────────────┬───────────────────────────────────────┘  │
│                      │                                          │
│                      │ (Service Endpoint / Privat nätverk)      │
│                      ▼                                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ snet-nordvik-storage                                      │  │
│  │                                                           │  │
│  │   stnordvik02albper01 (Blob Storage)                      │  │
│  │   - Container: felanmalningar (Bilder/JSON)               │  │
│  │   - Container: dokument (Kontrakt/Besiktning)             │  │
│  │   - Ingen public access                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────────┘
                       │ (Säker HTTP Webhook)
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│ Microsoft 365 / Power Automate Integration                      │
│  - Skapar rad i SharePoint-lista ("Felanmälningar")             │
│  - Akuta fel (Värme/Vatten/Lås) ➔ E-post/Teams-larm direkt     │
│  - Normala fel ➔ Notis till ansvarig förvaltare                │
└─────────────────────────────────────────────────────────────────┘