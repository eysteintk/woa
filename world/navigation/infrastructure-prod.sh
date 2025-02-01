#!/bin/bash
#
# infrastructure-prod.sh
#
# Creates the main application infrastructure
#

set -e

#############################################
# Configuration
#############################################
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
CONTAINER_APP_NAME="woa-prod-world-app"
CONTAINER_APP_ENV="woa-prod-world-env"
ENVIRONMENT_NAME="prod"
CLUSTER_NAME="woa-prod"
LOG_ANALYTICS_NAME="woa-prod-logs"
PUBSUB_NAME="woa-prod-pubsub"
ACR_NAME="woaprodregistry"
REDIS_NAME="woa-prod-redis"
IMAGE_NAME="woa-world-navigation"
IMAGE_TAG="latest"

# Check if Log Analytics workspace exists
if ! az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME &>/dev/null; then
    echo "Log Analytics workspace not found. Please ensure network infrastructure is deployed first."
    exit 1
fi

echo "Creating Application Insights for World service..."
az monitor app-insights component create \
    --app "${CONTAINER_APP_NAME}-insights" \
    --location $LOCATION \
    --resource-group $RESOURCE_GROUP \
    --workspace $LOG_ANALYTICS_NAME \
    --kind web \
    --application-type web \
    --output none

APPINSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
    --app "${CONTAINER_APP_NAME}-insights" \
    --resource-group $RESOURCE_GROUP \
    --query connectionString -o tsv)

#############################################
# Get Redis Connection Information
#############################################
echo "Getting Redis connection information..."
REDIS_HOST=$(az redis show --name $REDIS_NAME --resource-group $RESOURCE_GROUP --query hostName -o tsv)
REDIS_SSL_PORT=$(az redis show --name $REDIS_NAME --resource-group $RESOURCE_GROUP --query sslPort -o tsv)
REDIS_KEY=$(az redis list-keys --name $REDIS_NAME --resource-group $RESOURCE_GROUP --query primaryKey -o tsv)

#############################################
# Create Container App
#############################################
echo "Creating Container App..."
ACR_SERVER="${ACR_NAME}.azurecr.io"

# Retrieve ACR credentials
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query passwords[0].value -o tsv)

az containerapp create \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINER_APP_ENV \
    --image "$ACR_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
    --registry-server $ACR_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --target-port 80 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 5 \
    --secrets \
        "redis-password=$REDIS_KEY" \
    --env-vars \
        "REDIS_HOST=$REDIS_HOST" \
        "REDIS_PORT=$REDIS_SSL_PORT" \
        "REDIS_SSL=True" \
        "REDIS_PASSWORD=secretref:redis-password" \
        "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONNECTION_STRING" \
    --cpu 1.0 \
    --memory 2.0Gi \
    --output none

echo "
✅ Container App Deployment Complete! Important Information:
-------------------------------------------
🔮 App Name: $CONTAINER_APP_NAME
🌐 Environment: $CONTAINER_APP_ENV
📊 Log Analytics: $LOG_ANALYTICS_NAME
🔍 App Insights: ${CONTAINER_APP_NAME}-insights
🐳 Container Image: $ACR_SERVER/$IMAGE_NAME:$IMAGE_TAG
🔄 Redis Host: $REDIS_HOST
"