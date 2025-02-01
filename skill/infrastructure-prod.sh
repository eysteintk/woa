#!/bin/bash
# skill/infrastructure-prod.sh
set -e

# Variables
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
VNET_NAME="abs-vnet-we-prod"
CONTAINER_APP_NAME="woa-prod-skills-app"
CONTAINER_APP_ENV="woa-prod-skills-env"
PE_SUBNET="woa-private-endpoints"
CONTAINER_SUBNET="container-subnet"
CONFLUENT_ORG_NAME="WoA"
ENVIRONMENT_NAME="prod"
CLUSTER_NAME="woa-prod"
LOG_ANALYTICS_NAME="woa-prod-logs"
PUBSUB_NAME="woa-prod-pubsub"
ACR_NAME="woaprodregistry"
REDIS_NAME="woa-prod-redis"
IMAGE_NAME="woa-skill-network"
IMAGE_TAG="latest"

# Check if Log Analytics workspace exists first
if ! az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME &>/dev/null; then
    echo "Log Analytics workspace not found. Please ensure network infrastructure is deployed first."
    exit 1
fi

echo "Creating Application Insights for Skills service..."
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
# Get Web PubSub Connection String
#############################################
echo "Getting Web PubSub connection string..."
PUBSUB_CONNECTION_STRING=$(az webpubsub key show \
    --name $PUBSUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --query primaryConnectionString -o tsv)

#############################################
# Create Container App
#############################################
echo "Creating Container App..."
BOOTSTRAP_ENDPOINT=$(confluent kafka cluster describe $CLUSTER_ID -o json | jq -r '.endpoint')

az containerapp create \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINER_APP_ENV \
    --image "$ACR_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
    --registry-server $ACR_SERVER \
    --registry-username $ACR_USERNAME \
    --registry-password $ACR_PASSWORD \
    --registry-identity system \
    --image-pull-policy Always \
    --target-port 80 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 5 \
    --secrets \
        "ai-api-key=your-ai-api-key" \
        "redis-password=$REDIS_KEY" \
        "webpubsub-connection-string=$PUBSUB_CONNECTION_STRING" \
    --env-vars \
        "REDIS_HOST=$REDIS_HOST" \
        "REDIS_PORT=$REDIS_SSL_PORT" \
        "REDIS_SSL=True" \
        "REDIS_PASSWORD=secretref:redis-password" \
        "CONFLUENT_CLOUD_CLUSTER_ID=$CLUSTER_ID" \
        "CONFLUENT_CLOUD_ENVIRONMENT_ID=$ENV_ID" \
        "CONFLUENT_CLOUD_ORGANIZATION_ID=$CONFLUENT_ORG_ID" \
        "CONFLUENT_CLOUD_BOOTSTRAP_ENDPOINT=$BOOTSTRAP_ENDPOINT" \
        "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONNECTION_STRING" \
        "WEBPUBSUB_CONNECTION_STRING=secretref:webpubsub-connection-string" \
    --cpu 1.0 \
    --memory 2.0Gi \
    --scale-rule-name http-rule \
    --scale-rule-type http \
    --scale-rule-http-concurrency 100 \
    --scale-rule-metadata "scaleStableCooldown=60" "scaleOutCooldown=30" \
    --output none

# Configure Container App diagnostics
echo "Configuring Container App diagnostics..."
APP_ID=$(az containerapp show \
    --name $CONTAINER_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_ANALYTICS_NAME \
    --query id -o tsv)

az monitor diagnostic-settings create \
    --name "${CONTAINER_APP_NAME}-diagnostics" \
    --resource $APP_ID \
    --workspace $WORKSPACE_ID \
    --metrics '[{
        "category": "AllMetrics",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    }]' \
    --output none

# Create private endpoint for Web PubSub connectivity
echo "Creating private endpoint for Container Apps to Web PubSub..."
PUBSUB_ID=$(az webpubsub show \
    --name $PUBSUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)

az network private-endpoint create \
    --name "${CONTAINER_APP_NAME}-pubsub-pe" \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --subnet $PE_SUBNET \
    --private-connection-resource-id $PUBSUB_ID \
    --group-id "webpubsub" \
    --connection-name "${CONTAINER_APP_NAME}-pubsub-connection" \
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

Next Steps:
1. Build your Docker image:
   docker build -t $IMAGE_NAME:$IMAGE_TAG .

2. Tag the image for ACR:
   docker tag $IMAGE_NAME:$IMAGE_TAG $ACR_SERVER/$IMAGE_NAME:$IMAGE_TAG

3. Log in to ACR:
   az acr login --name $ACR_NAME

4. Push the image:
   docker push $ACR_SERVER/$IMAGE_NAME:$IMAGE_TAG

5. Monitor the deployment:
   az containerapp revision list --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP
"