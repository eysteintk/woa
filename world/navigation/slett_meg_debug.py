from azure.messaging.webpubsubclient import WebPubSubClient

url = "YOUR_WEBPUBSUB_CLIENT_URL"  # Replace with actual URL
client = WebPubSubClient(url)

client.join_group("navigation-events")
print("Successfully joined the group")
