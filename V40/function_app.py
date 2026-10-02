import os
import json
import uuid
import logging
import requests
from datetime import datetime
import azure.functions as func
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

HTML_FORM = """
<!DOCTYPE html>
<html>
<head>
    <title>Novatrix Kundtjänst (v40)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f4f4f9; }
        .container { max-width: 500px; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h2 { color: #333; }
        label { font-weight: bold; display: block; margin-top: 10px; }
        input, textarea { width: 100%; padding: 8px; margin-top: 5px; box-sizing: border-box; }
        button { margin-top: 15px; padding: 10px 15px; background: #0078d4; color: white; border: none; border-radius: 4px; cursor: pointer; }
        button:hover { background: #005a9e; }
        .success { color: green; font-weight: bold; padding: 10px; background-color: #e7f4e4; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>Novatrix Ärendeformulär (v40)</h2>
        <form method="POST" action="" enctype="multipart/form-data">
            <label>Namn:</label>
            <input type="text" name="name" required>
            
            <label>E-post:</label>
            <input type="email" name="email" required>
            
            <label>Ämne:</label>
            <input type="text" name="subject" required>
            
            <label>Beskrivning:</label>
            <textarea name="description" rows="4" required></textarea>
            
            <label>Bifoga fil (valfritt):</label>
            <input type="file" name="file">
            
            <button type="submit">Skicka ärende</button>
        </form>
    </div>
</body>
</html>
"""

@app.route(route="SubmitTicket", methods=["GET", "POST"], auth_level=func.AuthLevel.ANONYMOUS)
def SubmitTicket(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("SubmitTicket v40 mottog ett anrop.")

    if req.method == "GET":
        return func.HttpResponse(HTML_FORM, mimetype="text/html", status_code=200)

    if req.method == "POST":
        try:
            name = req.form.get('name')
            email = req.form.get('email')
            subject = req.form.get('subject')
            description = req.form.get('description')
            uploaded_file = req.files.get('file')

            ticket_id = f"NOV-{uuid.uuid4().hex[:6].upper()}"
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            connect_str = os.environ.get("AzureWebJobsStorage")
            container_name = "tickets"
            
            blob_service_client = BlobServiceClient.from_connection_string(connect_str)
            container_client = blob_service_client.get_container_client(container_name)

            try:
                container_client.create_container()
            except Exception:
                pass

            filename = ""
            blob_url = ""

            if uploaded_file:
                filename = f"{ticket_id}_{uploaded_file.filename}"
                file_bytes = uploaded_file.read()
                if file_bytes:
                    blob_client = container_client.get_blob_client(filename)
                    blob_client.upload_blob(file_bytes, overwrite=True)
                    account_name = blob_service_client.account_name
                    blob_url = f"https://{account_name}.blob.core.windows.net/{container_name}/{filename}"

            ticket_data = {
                "ticket_id": ticket_id,
                "timestamp": timestamp,
                "name": name,
                "email": email,
                "subject": subject,
                "description": description,
                "filename": filename,
                "blob_url": blob_url
            }

            json_filename = f"ticket_{ticket_id}.json"
            json_blob_client = container_client.get_blob_client(json_filename)
            json_blob_client.upload_blob(json.dumps(ticket_data, ensure_ascii=False, indent=2), overwrite=True)

            power_automate_url = os.environ.get("POWER_AUTOMATE_URL", "")
            if power_automate_url and "http" in power_automate_url:
                try:
                    requests.post(power_automate_url, json=ticket_data, timeout=5)
                except Exception as e:
                    logging.error(f"Power Automate Trigger Error: {e}")

            success_html = HTML_FORM.replace(
                '<h2>Novatrix Ärendeformulär (v40)</h2>',
                f'<h2>Novatrix Ärendeformulär (v40)</h2><p class="success">Tack! Ditt ärende har registrerats. Ärende-ID: {ticket_id}</p>'
            )
            return func.HttpResponse(success_html, mimetype="text/html", status_code=200)

        except Exception as e:
            logging.error(f"Fel vid hantering av ärende: {e}")
            return func.HttpResponse(f"Ett internt fel uppstod: {str(e)}", status_code=500)

    return func.HttpResponse("Metoden stöds ej", status_code=405)