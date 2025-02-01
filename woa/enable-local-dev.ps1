#!/bin/bash
# infrastructure-prod.sh
set -e

####################################
# Pre-requisites & Environment Checks
####################################

# Ensure jq is installed.
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq (e.g., sudo apt-get install jq)."
    exit 1
fi

# Ensure that the Azure Static Web Apps extension is installed and updated.
if ! az extension show --name staticwebapp &> /dev/null; then
    echo "Azure Static Web Apps extension not found. Installing..."
    az extension add --name staticwebapp
else
    echo "Updating Azure Static Web Apps extension..."
    az extension update --name staticwebapp
fi

# Verify required Okta environment variables.
if [ -z "$OKTA_API_TOKEN" ] || [ -z "$OKTA_DOMAIN" ]; then
    echo "Error: Please set the OKTA_API_TOKEN and OKTA_DOMAIN environment variables."
    echo "Example:"
    echo "  export OKTA_API_TOKEN=\"your_okta_api_token\""
    echo "  export OKTA_DOMAIN=\"your_okta_domain\"  # e.g., dev-123456.okta.com"
    exit 1
fi

####################################
# Configuration
####################################

RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
APP_NAME="woa-prod-app"
STATIC_WEB_APP_NAME="woa-prod-spa"
STATIC_WEB_APP_SKU="Standard"
LOG_ANALYTICS_NAME="woa-prod-logs"

# Retrieve GitHub information from the current git remote URL.
GITHUB_TOKEN=$(gh auth token)
GITHUB_ORG=$(git config --get remote.origin.url | sed -n 's/.*github\.com[:/]\([^/]*\)\/.*/\1/p')
GITHUB_REPO=$(git config --get remote.origin.url | sed -n 's/.*github\.com[:/][^/]*\/\(.*\)\.git/\1/p')

####################################
# Check for Prerequisite Azure Resources
####################################

if ! az monitor log-analytics workspace show \
      --resource-group "$RESOURCE_GROUP" \
      --workspace-name "$LOG_ANALYTICS_NAME" \
      --output none 2>/dev/null; then
    echo "❌ Log Analytics workspace '$LOG_ANALYTICS_NAME' not found in resource group '$RESOURCE_GROUP'."
    echo "Please ensure your network infrastructure is deployed first."
    exit 1
fi

####################################
# Create Application Insights
####################################

echo "Creating Application Insights..."
az monitor app-insights component create \
    --app "${APP_NAME}-insights" \
    --location "$LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --workspace "$LOG_ANALYTICS_NAME" \
    --kind web \
    --application-type web \
    --output none

####################################
# Create or Update Static Web App with GitHub Integration
####################################

echo "Checking for existing Static Web App..."
if az staticwebapp show --name "$STATIC_WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
    echo "Static Web App '$STATIC_WEB_APP_NAME' already exists in resource group '$RESOURCE_GROUP'. Skipping creation."
else
    echo "Creating Static Web App..."
    az staticwebapp create \
        --name "$STATIC_WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$STATIC_WEB_APP_SKU" \
        --source "https://github.com/$GITHUB_ORG/$GITHUB_REPO" \
        --branch "main" \
        --token "$GITHUB_TOKEN" \
        --output none
fi

####################################
# Enable Enterprise-grade Edge
####################################

echo "Enabling Enterprise-grade Edge..."
az staticwebapp enterprise-edge enable \
    --name "$STATIC_WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --output none || echo "Enterprise-grade Edge already enabled or conflict occurred."

####################################
# Retrieve Static Web App Hostname
####################################

echo "Retrieving Static Web App hostname..."
STATIC_WEB_APP_HOSTNAME=$(az staticwebapp show \
    --name "$STATIC_WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "defaultHostname" \
    --output tsv)
echo "Static Web App Hostname: $STATIC_WEB_APP_HOSTNAME"

####################################
# Create Okta OIDC Application Integration (if not already provided)
####################################

if [ -z "$OKTA_CLIENT_ID" ] || [ -z "$OKTA_CLIENT_SECRET" ]; then
    echo "Creating Okta OIDC Application Integration..."
    OKTA_PAYLOAD=$(cat <<EOF
{
  "name": "oidc_client",
  "label": "Azure Static Web App Auth",
  "signOnMode": "OPENID_CONNECT",
  "credentials": {
    "oauthClient": {
      "autoKeyRotation": true,
      "token_endpoint_auth_method": "client_secret_post"
    }
  },
  "settings": {
    "oauthClient": {
      "redirect_uris": [
        "https://${STATIC_WEB_APP_HOSTNAME}/.auth/login/okta/callback"
      ],
      "response_types": [
        "code"
      ],
      "grant_types": [
        "authorization_code"
      ],
      "application_type": "web"
    }
  }
}
EOF
)
    OKTA_RESPONSE=$(curl -s -X POST "https://${OKTA_DOMAIN}/api/v1/apps" \
      -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$OKTA_PAYLOAD")
    OKTA_CLIENT_ID=$(echo "$OKTA_RESPONSE" | jq -r '.credentials.oauthClient.client_id')
    OKTA_CLIENT_SECRET=$(echo "$OKTA_RESPONSE" | jq -r '.credentials.oauthClient.client_secret')
    if [ "$OKTA_CLIENT_ID" = "null" ] || [ "$OKTA_CLIENT_SECRET" = "null" ]; then
        echo "Error creating Okta integration. Response:"
        echo "$OKTA_RESPONSE"
        exit 1
    fi
    echo "Okta integration created successfully."
    echo "Okta Client ID: $OKTA_CLIENT_ID"
    echo "Okta Client Secret: $OKTA_CLIENT_SECRET"
fi

####################################
# Update Authentication Configuration via ARM REST API
####################################
# (Workaround for CLI limitations: We use az rest to PATCH the auth settings.)
echo "Updating authentication configuration via ARM REST API..."

# Retrieve the current subscription ID.
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Build the resource URI for the Static Web App configuration.
CONFIG_URI="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/staticSites/${STATIC_WEB_APP_NAME}/config?api-version=2022-03-01"

# Create the payload with the auth configuration.
AUTH_PAYLOAD=$(cat <<EOF
{
  "properties": {
    "auth": {
      "identityProviders": {
        "customOpenIdConnect": {
          "registration": {
            "clientId": "$OKTA_CLIENT_ID",
            "clientSecret": "$OKTA_CLIENT_SECRET",
            "openIdConnectConfiguration": {
              "authorizationEndpoint": "https://${OKTA_DOMAIN}/oauth2/v1/authorize",
              "tokenEndpoint": "https://${OKTA_DOMAIN}/oauth2/v1/token",
              "issuer": "https://${OKTA_DOMAIN}",
              "clientCredentialAuthenticationScheme": "header"
            }
          }
        }
      }
    }
  }
}
EOF
)

echo "Sending PATCH request to update auth configuration..."
az rest --method PATCH --uri "$CONFIG_URI" --body "$AUTH_PAYLOAD" --output none

####################################
# Configure Monitoring
####################################

echo "Configuring Static Web App diagnostics..."
STATIC_WEB_APP_ID=$(az staticwebapp show \
    --name "$STATIC_WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query id -o tsv)
az monitor diagnostic-settings create \
    --name "${STATIC_WEB_APP_NAME}-diagnostics" \
    --resource "$STATIC_WEB_APP_ID" \
    --workspace "$WORKSPACE_ID" \
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

####################################
# Set GitHub Deployment Token
####################################

echo "Setting up GitHub deployment..."
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
    --name "$STATIC_WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.apiKey" -o tsv)
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --body "$DEPLOYMENT_TOKEN" \
    --repo "$GITHUB_ORG/$GITHUB_REPO"

####################################
# Output Important Information
####################################

echo "Getting deployment information..."
STATIC_WEB_APP_HOSTNAME=$(az staticwebapp show \
    --name "$STATIC_WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "defaultHostname" \
    --output tsv)
APPINSIGHTS_KEY=$(az monitor app-insights component show \
    --app "${APP_NAME}-insights" \
    --resource-group "$RESOURCE_GROUP" \
    --query "instrumentationKey" \
    --output tsv)

echo "
✅ Deployment Complete! Important endpoints:
----------------------------------------
🌐 Static Web App: https://${STATIC_WEB_APP_HOSTNAME}
🔑 Application Insights Key: $APPINSIGHTS_KEY
🌟 GitHub Repo: https://github.com/$GITHUB_ORG/$GITHUB_REPO (Branch: main)
"
