import azure.functions as func
import logging
import json
import os
import base64
import datetime
import uuid
import hmac

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

DEBUG = os.environ.get("DEBUG_ERRORS") == "1"
_jwk_client = None


def _json(body, status: int) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(body), status_code=status, mimetype="application/json")


def _error(message: str, status: int, detail: str = "") -> func.HttpResponse:
    """Returnerar ett fel. Detaljer visas bara om appinställningen DEBUG_ERRORS=1 är satt."""
    body = {"status": "error", "message": message}
    if DEBUG and detail:
        body["detail"] = detail[:500]
    return _json(body, status)


def _validate_token(req: func.HttpRequest) -> dict:
    """Validerar Entra ID-token (signatur, utfärdare, målgrupp, giltighetstid). Kastar PermissionError vid fel."""
    import jwt
    from jwt import PyJWKClient

    global _jwk_client
    tenant = os.environ.get("ENTRA_TENANT_ID")
    client = os.environ.get("ENTRA_CLIENT_ID")
    if not tenant or not client:
        raise RuntimeError("ENTRA_TENANT_ID/ENTRA_CLIENT_ID saknas")

    auth = req.headers.get("Authorization", "")
    if not auth.lower().startswith("bearer "):
        raise PermissionError("Inloggning krävs.")
    token = auth[7:].strip()

    if _jwk_client is None:
        _jwk_client = PyJWKClient(f"https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys")
    try:
        key = _jwk_client.get_signing_key_from_jwt(token).key
        return jwt.decode(
            token, key, algorithms=["RS256"], audience=client,
            issuer=f"https://login.microsoftonline.com/{tenant}/v2.0",
        )
    except jwt.PyJWTError as e:
        raise PermissionError(f"Ogiltig token: {e}")


def _table():
    from azure.identity import DefaultAzureCredential
    from azure.data.tables import TableServiceClient
    service = TableServiceClient(endpoint=os.environ["DATA_TABLE_ENDPOINT"], credential=DefaultAzureCredential())
    return service.get_table_client("felanmalningar")


@app.route(route="felanmalan", methods=["POST"])
def submit_felanmalan(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Mottog ny felanmälan från frontend.")

    try:
        import requests
        from azure.identity import DefaultAzureCredential
        from azure.storage.blob import BlobServiceClient
    except ImportError as imp_err:
        logging.error(f"Importfel: {imp_err}")
        return _error("Serverkonfigurationsfel.", 500, f"Importfel: {imp_err}")

    try:
        # 1. Vem är det? Bara inloggade användare får skapa ärenden.
        try:
            claims = _validate_token(req)
        except PermissionError as pe:
            return _error("Du måste logga in.", 401, str(pe))
        oid = claims.get("oid")
        epost = claims.get("preferred_username") or claims.get("email") or ""
        namn = claims.get("name") or ""
        if not oid:
            return _error("Du måste logga in.", 401, "Token saknar oid")

        # 2. Validera indata
        try:
            req_body = req.get_json()
        except ValueError:
            return _error("Ogiltig JSON i anropskroppen.", 400)
        if not isinstance(req_body, dict):
            return _error("Förväntade ett JSON-objekt.", 400)

        rubrik = req_body.get("rubrik")
        beskrivning = req_body.get("beskrivning")
        fastighet = req_body.get("fastighet")
        lagenhet = req_body.get("lagenhet")
        kategori = req_body.get("kategori")
        bild_base64 = req_body.get("bildBase64")
        bild_filnamn = req_body.get("bildFilnamn") or "bild.jpg"

        if not all([rubrik, beskrivning, fastighet, lagenhet, kategori]):
            return _error("Obligatoriska fält saknas.", 400)
        if not bild_base64:
            return _error("Bild saknas. En felanmälan måste ha en bild.", 400)

        arende_id = f"NV-{datetime.datetime.now():%Y%m%d}-{uuid.uuid4().hex[:6].upper()}"

        if "," in bild_base64:
            bild_base64 = bild_base64.split(",", 1)[1]
        try:
            image_bytes = base64.b64decode(bild_base64, validate=True)
        except Exception:
            return _error("Ogiltig bild.", 400)

        # 3. Spara bilden (managed identity, ingen nyckel)
        account_url = os.environ.get("DATA_STORAGE_ACCOUNT_URL")
        if not account_url:
            return _error("Serverkonfigurationsfel.", 500, "DATA_STORAGE_ACCOUNT_URL saknas")
        credential = DefaultAzureCredential()
        service = BlobServiceClient(account_url=account_url, credential=credential)
        ext = os.path.splitext(bild_filnamn)[1] or ".jpg"
        blob_name = f"{arende_id}{ext}"
        service.get_blob_client(container="felanmalningar", blob=blob_name).upload_blob(image_bytes, overwrite=True)

        # 4. Spara ärendet med ägarens ID (det är det som gör att hyresgästen bara ser sina egna)
        _table().create_entity({
            "PartitionKey": oid,
            "RowKey": arende_id,
            "rubrik": rubrik,
            "beskrivning": beskrivning,
            "fastighet": fastighet,
            "lagenhet": lagenhet,
            "kategori": kategori,
            "status": "Mottagen",
            "bildFilnamn": blob_name,
            "epost": epost,
            "skapad": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
        })

        # 5. Skicka till Power Automate (SharePoint, Teams, mejl)
        notifierad = True
        power_automate_url = os.environ.get("POWER_AUTOMATE_URL")
        if not power_automate_url:
            logging.error("POWER_AUTOMATE_URL är inte satt.")
            notifierad = False
        else:
            payload = {
                "arendeId": arende_id, "rubrik": rubrik, "beskrivning": beskrivning,
                "fastighet": fastighet, "lagenhet": lagenhet, "kategori": kategori,
                "epost": epost, "inskickadAv": namn,
                "bildFilnamn": blob_name, "bildInnehall": bild_base64,
                "blobPath": f"/felanmalningar/{blob_name}",
            }
            try:
                requests.post(power_automate_url, json=payload, timeout=10).raise_for_status()
            except Exception as flow_err:
                # Ärendet är redan sparat, så logga felet men svara inte med fel till användaren
                logging.error(f"Kunde inte notifiera Power Automate: {flow_err}")
                notifierad = False

        return _json({"status": "success", "message": "Felanmälan mottagen.", "arendeId": arende_id, "notifierad": notifierad}, 200)

    except Exception as e:
        logging.exception(f"Fel vid behandling av felanmälan: {e}")
        return _error("Något gick fel vid behandlingen.", 500, f"{type(e).__name__}: {e}")


@app.route(route="mina-anmalningar", methods=["GET"])
def mina_anmalningar(req: func.HttpRequest) -> func.HttpResponse:
    try:
        try:
            claims = _validate_token(req)
        except PermissionError as pe:
            return _error("Du måste logga in.", 401, str(pe))
        oid = claims.get("oid")
        if not oid:
            return _error("Du måste logga in.", 401, "Token saknar oid")

        # Least privilege: frågan filtreras alltid på den inloggades eget ID, aldrig på något klienten skickar
        rows = _table().query_entities(query_filter="PartitionKey eq @oid", parameters={"oid": oid})
        items = [{
            "arendeId": r["RowKey"], "rubrik": r.get("rubrik"), "kategori": r.get("kategori"),
            "fastighet": r.get("fastighet"), "lagenhet": r.get("lagenhet"),
            "status": r.get("status"), "skapad": r.get("skapad") or "",
        } for r in rows]
        items.sort(key=lambda x: x["skapad"], reverse=True)
        return _json({"status": "success", "anmalningar": items}, 200)

    except Exception as e:
        logging.exception(f"Fel vid hämtning av anmälningar: {e}")
        return _error("Något gick fel vid behandlingen.", 500, f"{type(e).__name__}: {e}")


GILTIGA_STATUS = {"Mottagen", "Under behandling", "Åtgärdad"}


@app.route(route="uppdatera-status", methods=["POST"])
def uppdatera_status(req: func.HttpRequest) -> func.HttpResponse:
    """Anropas av Power Automate när en förvaltare ändrar status i SharePoint-listan.
    Ingen inloggad person finns bakom anropet, så det skyddas med en delad nyckel i headern x-api-key."""
    try:
        forvantad = os.environ.get("STATUS_API_KEY", "")
        if not forvantad:
            return _error("Tjänsten är inte konfigurerad.", 503, "STATUS_API_KEY saknas")
        angiven = req.headers.get("x-api-key", "")
        if not hmac.compare_digest(angiven.encode(), forvantad.encode()):
            return _error("Åtkomst nekad.", 401)

        try:
            body = req.get_json()
        except ValueError:
            return _error("Ogiltig JSON.", 400)
        if not isinstance(body, dict):
            return _error("Förväntade ett JSON-objekt.", 400)

        arende_id = body.get("arendeId")
        status = body.get("status")
        if not arende_id or status not in GILTIGA_STATUS:
            return _error("arendeId saknas eller status är ogiltig.", 400)

        table = _table()
        rader = list(table.query_entities(query_filter="RowKey eq @id", parameters={"id": arende_id}))
        if not rader:
            return _error("Ärendet hittades inte.", 404)

        table.update_entity(
            {"PartitionKey": rader[0]["PartitionKey"], "RowKey": arende_id, "status": status,
             "uppdaterad": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z"},
            mode="merge",
        )
        logging.info(f"Status för {arende_id} ändrad till {status}.")
        return _json({"status": "success", "arendeId": arende_id, "nyStatus": status}, 200)

    except Exception as e:
        logging.exception(f"Fel vid statusuppdatering: {e}")
        return _error("Något gick fel vid behandlingen.", 500, f"{type(e).__name__}: {e}")