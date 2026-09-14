import os
import datetime
from flask import Flask, request
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = Flask(__name__)

# Ändra till DITT exakta namn på lagringskontot
STORAGE_ACCOUNT_NAME = "stnovatrixv37albin" 
CONTAINER_NAME = "tickets"
ACCOUNT_URL = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"

# Hämtar automatiskt id-novatrix-app från VM:en
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(account_url=ACCOUNT_URL, credential=credential)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        title = request.form.get('title', 'Inget ämne')
        content = request.form.get('content', '')
        file = request.files.get('file')
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        
        # 1. Spara ärendet som textfil i Blob Storage
        ticket_blob_name = f"ticket-{timestamp}.txt"
        ticket_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=ticket_blob_name)
        ticket_data = f"Titel: {title}\nDatum: {timestamp}\n\nBeskrivning:\n{content}"
        ticket_client.upload_blob(ticket_data, overwrite=True)

        # 2. Spara bifogad fil/bilaga om en sådan har valts
        if file and file.filename != '':
            file_blob_name = f"attachment-{timestamp}-{file.filename}"
            file_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=file_blob_name)
            file_client.upload_blob(file.read(), overwrite=True)

        return "<h2>Ärendet och bilagan har sparats i Azure Blob Storage!</h2><a href='/'>Skicka ett till</a>"

    return '''
    <h2>Novatrix Ärendeformulär</h2>
    <form method="POST" enctype="multipart/form-data">
        <p><label>Titel:</label><br><input type="text" name="title" required></p>
        <p><label>Beskrivning:</label><br><textarea name="content" rows="4" required></textarea></p>
        <p><label>Bifoga fil (bilaga):</label><br><input type="file" name="file"></p>
        <p><button type="submit">Skicka ärende</button></p>
    </form>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)