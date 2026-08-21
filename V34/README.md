# Azure – Uppgift 1

**Namn:** Albin Persson
**Kurs:** Azure v.34

## Delmoment 1 – Sätt upp kursrepo på GitHub

Jag skapade ett publikt GitHub-repo, `azure-novatrix`, som ska följa mig genom hela kursen. Repot innehåller en README med mitt namn, kursnamn och en översikt över veckornas mappstruktur. Varje vecka läggs i en egen undermapp med tillhörande kod och konfiguration.

**Verifiering:** Repot är publikt och nåbart.

![alt text](github-repo.png)

## Delmoment 2 – Provisionera en virtuell server

Jag provisionerade en virtuell maskin i Azure baserad på Ubuntu 22.04. Jag valde storleken `Standard_B2ats_v2`, eftersom den är kostnadseffektiv och fullt tillräcklig för att köra en enkel Nginx-sida utan konstant hög belastning. Resursgrupp och VM namngavs enligt kursens namnkonvention: `rg-novatrix` och `vm-novatrix-web`.

**Verifiering:** VM:en skapades utan fel och tilldelades den publika IP-adressen `172.160.228.10`.

![alt text](vm-created.png)


## Delmoment 3 – Konfigurera värdmiljön

Först så var jag tvungen och sätta behörighet på nyckeln i terminal. Det gjorde jag med följande kod:

```bash
icacls .\vm-novatrix-web_key.pem /inheritance:r
icacls .\vm-novatrix-web_key.pem /grant:r "$($env:USERNAME):R"
```

Jag anslöt till servern via SSH med kommandot:

```bash
ssh -i vm-novatrix-web_key.pem azureuser@172.160.228.10
```

Därefter installerade jag webbservern Nginx:

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable nginx
```

**Verifiering:** Jag kontrollerade att Nginx var igång med `sudo systemctl status nginx`, som visade status `active (running)`. Se skärmdump nedan.

![alt text](nginx-status.png)

## Delmoment 4 – Driftsätt kundtjänstsidan med ärendeformulär

Jag skapade en enkel webbsida, `index.html`, som presenterar Novatrix AB och innehåller ett ärendeformulär med fälten namn, e-post och meddelande. Sidan laddades upp till servern och ersatte Nginx standardsida i `/var/www/html/index.html`.

Jag fick lite problem med att ansluta till webbsidan men efter att jag öpnat port 80 fungerade det.

![alt text](port-opened.png)

**Kod:**

```html
<!DOCTYPE html>
<html lang="sv">
<head>
  <meta charset="UTF-8">
  <title>Novatrix AB – Kundtjänst</title>
</head>
<body>
  <h1>Novatrix AB</h1>
  <p>Välkommen till vår kundtjänst. Fyll i formuläret nedan så återkommer vi.</p>

  <form>
    <label for="namn">Namn:</label><br>
    <input type="text" id="namn" name="namn"><br><br>

    <label for="epost">E-post:</label><br>
    <input type="email" id="epost" name="epost"><br><br>

    <label for="meddelande">Meddelande:</label><br>
    <textarea id="meddelande" name="meddelande"></textarea><br><br>

    <button type="submit">Skicka</button>
  </form>
</body>
</html>
```

**Verifiering:** Sidan är nåbar på `http://172.160.228.10` och visar Novatrix kundtjänstsida med formuläret synligt.

![alt text](support-page.png)

## Delmoment 5 – Verifiera och dokumentera

Samtliga steg ovan har verifierats löpande genom varje delmoment: VM:en är provisionerad och nåbar, Nginx körs, och kundtjänstsidan med ärendeformuläret visas korrekt på serverns publika IP.