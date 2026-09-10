import os
import datetime
from flask import Flask, request
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = Flask(__name__)


STORAGE_ACCOUNT_NAME = "stnovatrixv37" 
CONTAINER_NAME = "tickets"
ACCOUNT_URL = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"

# Hämtar automatiskt id-novatrix-app som är kopplad till VM:en
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(account_url=ACCOUNT_URL, credential=credential)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        title = request.form.get('title', 'Inget ämne')
        content = request.form.get('content', '')
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        
        # Spara ärendet som textfil i Blob Storage
        ticket_blob_name = f"ticket-{timestamp}.txt"
        ticket_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=ticket_blob_name)
        ticket_data = f"Titel: {title}\nDatum: {timestamp}\n\nBeskrivning:\n{content}"
        
        ticket_client.upload_blob(ticket_data, overwrite=True)
        return "<h2>Ärendet har sparats i Azure Blob Storage!</h2><a href='/'>Skicka ett till</a>"

    return '''
    <h2>Novatrix Ärendeformulär</h2>
    <form method="POST">
        <p><label>Titel:</label><br><input type="text" name="title" required></p>
        <p><label>Beskrivning:</label><br><textarea name="content" rows="4" required></textarea></p>
        <p><button type="submit">Skicka ärende</button></p>
    </form>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)