#!/bin/bash
# Configuration
RESOURCE_GROUP="abs-rg-we-prod"
WEB_PUBSUB_NAME="woa-prod-pubsub"

az webpubsub network-rule update \
    --name $WEB_PUBSUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --public-network false \
    --connection-name "${WEB_PUBSUB_NAME}-connection" \
    --allow ServerConnection ClientConnection RESTAPI