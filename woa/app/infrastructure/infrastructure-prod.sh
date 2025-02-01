#!/bin/bash
# woa/app/infrastructure/infrastructure-prod.sh
set -e

# Configuration
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
VNET_NAME="abs-vnet-we-prod"
PE_SUBNET="woa-private-endpoints"
APP_NAME="woa-prod-app"
STATIC_WEB_APP_NAME="woa-prod-spa"
STATIC_WEB_APP_SKU="Standard"
FRONTDOOR_NAME="woa-prod-fd"
FRONTDOOR_ENDPOINT_NAME="woa-prod-fd-endpoint"
FRONTDOOR_ORIGIN_GROUP="woa-prod-static-origin-group"
FRONTDOOR_ORIGIN="woa-prod-static-origin"
LOG_ANALYTICS_NAME="woa-prod-logs"
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
WORKSPACE_ID="/subscriptions/367fc58b-579a-44ff-aaf6-769df039fde6/resourceGroups/abs-rg-we-prod/providers/Microsoft.OperationalInsights/workspaces/woa-prod-logs"
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
VNET_NAME="abs-vnet-we-prod"
PE_SUBNET="woa-private-endpoints"
PE_NSG="abs-nsg-woa-pe-we-prod"


# Check if Log Analytics workspace exists first
if ! az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME --output none 2>/dev/null; then
    echo "❌ Log Analytics workspace not found. Please ensure network infrastructure is deployed first."
    exit 1
fi

#############################################
# 1. Create NSG for the Private Endpoint Subnet
#############################################
echo "Configuring rules for NSG '$PE_NSG'..."
# Allow VNet traffic with priority 100
az network nsg rule create \
    --nsg-name $PE_NSG \
    --resource-group $RESOURCE_GROUP \
    --name AllowVNetTraffic \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol "*" \
    --source-address-prefixes VirtualNetwork \
    --destination-address-prefixes VirtualNetwork \
    --destination-port-ranges "*" \
    --output none

# Allow Private Endpoints with priority 110
az network nsg rule create \
    --nsg-name $PE_NSG \
    --resource-group $RESOURCE_GROUP \
    --name AllowPrivateEndpointsTraffic \
    --priority 110 \
    --direction Inbound \
    --access Allow \
    --protocol "*" \
    --source-address-prefixes VirtualNetwork \
    --destination-address-prefixes "*" \
    --destination-port-ranges "*" \
    --output none

# Deny all inbound traffic by default (company policy)
az network nsg rule create \
    --nsg-name $PE_NSG \
    --resource-group $RESOURCE_GROUP \
    --name DenyAllInbound \
    --priority 4096 \
    --direction Inbound \
    --access Deny \
    --protocol "*" \
    --source-address-prefixes "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "*" \
    --output none

#############################################
# 2. Associate NSG with Private Endpoint Subnet
#############################################
echo "Associating NSG '$PE_NSG' with subnet '$PE_SUBNET'..."
az network vnet subnet update \
    --name $PE_SUBNET \
    --vnet-name $VNET_NAME \
    --resource-group $RESOURCE_GROUP \
    --network-security-group $PE_NSG \
    --output none



#############################################
# Create Application Insights
#############################################
echo "Creating Application Insights..."
az monitor app-insights component create \
    --app "${APP_NAME}-insights" \
    --location $LOCATION \
    --resource-group $RESOURCE_GROUP \
    --workspace $LOG_ANALYTICS_NAME \
    --kind web \
    --application-type web \
    --output none

#############################################
# Create Static Web App with Okta Auth Config
#############################################
echo "Creating/Updating Static Web App..."
az staticwebapp create \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku $STATIC_WEB_APP_SKU \
    --output none

# Configure auth settings
echo "Configuring authorization settings..."
az staticwebapp update \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --auth-provider-enabled true \
    --output none

# Add default routes configuration for auth
ROUTES_CONFIG='{
    "routes": [
        {
            "route": "/*",
            "allowedRoles": ["authenticated"]
        }
    ],
    "auth": {
        "identityProviders": {
            "customOpenIdConnect": {
                "enabled": true,
                "registration": {
                    "clientId": "OKTA_CLIENT_ID",
                    "clientSecret": "OKTA_CLIENT_SECRET",
                    "openIdConnectConfiguration": {
                        "authorizationEndpoint": "https://YOUR_DEV_OKTA_DOMAIN/oauth2/v1/authorize",
                        "tokenEndpoint": "https://YOUR_DEV_OKTA_DOMAIN/oauth2/v1/token",
                        "issuer": "https://YOUR_DEV_OKTA_DOMAIN",
                        "clientCredentialAuthenticationScheme": "header"
                    }
                }
            }
        }
    }
}'

echo "Updating routes configuration for authentication..."
az staticwebapp config set \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --config "$ROUTES_CONFIG" \
    --output none


#############################################
# Create Front Door Profile and Endpoint
#############################################
echo "Creating Front Door profile..."
az afd profile create \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --sku Standard_AzureFrontDoor \
    --output none

echo "Creating Front Door endpoint..."
az afd endpoint create \
    --endpoint-name $FRONTDOOR_ENDPOINT_NAME \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --enabled-state Enabled \
    --output none

#############################################
# Create Origin Group and Origin
#############################################
echo "Creating Front Door origin group..."
az afd origin-group create \
    --origin-group-name $FRONTDOOR_ORIGIN_GROUP \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --probe-path "/" \
    --probe-protocol Https \
    --probe-request-type HEAD \
    --probe-interval-in-seconds 120 \
    --sample-size 4 \
    --successful-samples-required 3 \
    --additional-latency-in-milliseconds 50 \
    --output none

echo "Creating Front Door origin..."
STATIC_WEB_APP_HOSTNAME=$(az staticwebapp show \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "defaultHostname" \
    --output tsv)

az afd origin create \
    --origin-name $FRONTDOOR_ORIGIN \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --origin-group-name $FRONTDOOR_ORIGIN_GROUP \
    --host-name $STATIC_WEB_APP_HOSTNAME \
    --origin-host-header $STATIC_WEB_APP_HOSTNAME \
    --priority 1 \
    --weight 1000 \
    --enabled-state Enabled \
    --http-port 80 \
    --https-port 443 \
    --enforce-certificate-name-check true \
    --output none

#############################################
# Create Rule Set and Security Headers
#############################################
echo "Creating rule set for security headers..."
az afd rule-set create \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --rule-set-name "securityheaders" \
    --output none

echo "Adding HSTS security header rule..."
az afd rule create \
    --rule-set-name "securityheaders" \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --order 1 \
    --rule-name "hsts" \
    --action-name "ModifyResponseHeader" \
    --header-action "Append" \
    --header-name "Strict-Transport-Security" \
    --header-value "max-age=31536000" \
    --output none

echo "Adding X-Content-Type-Options security header rule..."
az afd rule create \
    --rule-set-name "securityheaders" \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --order 2 \
    --rule-name "nosniff" \
    --action-name "ModifyResponseHeader" \
    --header-action "Append" \
    --header-name "X-Content-Type-Options" \
    --header-value "nosniff" \
    --output none

echo "Adding X-Frame-Options security header rule..."
az afd rule create \
    --rule-set-name "securityheaders" \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --order 3 \
    --rule-name "framedenied" \
    --action-name "ModifyResponseHeader" \
    --header-action "Append" \
    --header-name "X-Frame-Options" \
    --header-value "DENY" \
    --output none

#############################################
# Create Route with Rule Set
#############################################
echo "Checking if Front Door route exists..."
if ! az afd route show \
    --route-name "defaultroute" \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --endpoint-name $FRONTDOOR_ENDPOINT_NAME \
    --output none 2>/dev/null; then
    echo "Creating Front Door route..."
    az afd route create \
        --route-name "defaultroute" \
        --profile-name $FRONTDOOR_NAME \
        --resource-group $RESOURCE_GROUP \
        --endpoint-name $FRONTDOOR_ENDPOINT_NAME \
        --origin-group $FRONTDOOR_ORIGIN_GROUP \
        --supported-protocols Https \
        --patterns-to-match "/*" \
        --forwarding-protocol HttpsOnly \
        --https-redirect Enabled \
        --link-to-default-domain Enabled \
        --rule-sets "securityheaders" \
        --output none
else
    echo "✓ Front Door route already exists"
fi

#############################################
# Configure Monitoring
#############################################
#!/bin/bash
# Replace the Static Web App diagnostics section with:

echo "Configuring Static Web App diagnostics..."
STATIC_WEB_APP_ID=$(az staticwebapp show \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)

WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_ANALYTICS_NAME \
    --query id -o tsv)

az monitor diagnostic-settings create \
    --name "${STATIC_WEB_APP_NAME}-diagnostics" \
    --resource $STATIC_WEB_APP_ID \
    --workspace $WORKSPACE_ID \
    --metrics '[
        {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {
                "days": 0,
                "enabled": false
            }
        }
    ]' \
    --output none

echo "Configuring Front Door diagnostics..."
FRONTDOOR_ID=$(az afd profile show \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)

az monitor diagnostic-settings create \
    --name "${FRONTDOOR_NAME}-diagnostics" \
    --resource $FRONTDOOR_ID \
    --workspace $WORKSPACE_ID \
    --logs '[
        {
            "category": "FrontDoorAccessLog",
            "enabled": true
        },
        {
            "category": "FrontDoorHealthProbeLog",
            "enabled": true
        },
        {
            "category": "FrontDoorWebApplicationFirewallLog",
            "enabled": true
        }
    ]' \
    --metrics '[{
        "category": "AllMetrics",
        "enabled": true,
        "retentionPolicy": {
            "enabled": false,
            "days": 0
        }
    }]' \
    --output none

#############################################
# Output Important Information
#############################################
echo "Getting deployment information..."
FRONTDOOR_ENDPOINT=$(az afd endpoint show \
    --endpoint-name $FRONTDOOR_ENDPOINT_NAME \
    --profile-name $FRONTDOOR_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "hostName" \
    --output tsv)

APPINSIGHTS_KEY=$(az monitor app-insights component show \
    --app "${APP_NAME}-insights" \
    --resource-group $RESOURCE_GROUP \
    --query "instrumentationKey" \
    --output tsv)

echo "
✅ Deployment Complete! Important endpoints:
----------------------------------------
🌐 Static Web App: https://${STATIC_WEB_APP_HOSTNAME}
🚀 Front Door Endpoint: https://$FRONTDOOR_ENDPOINT
🔑 Application Insights Key: $APPINSIGHTS_KEY
"