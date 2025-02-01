#!/bin/bash
# infrastructure-prod.sh
set -e

####################################
# Pre-requisites & Environment Checks
####################################
# Ensure jq is installed.
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Install with e.g., sudo apt-get install jq."
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
  echo "Error: Please set OKTA_API_TOKEN and OKTA_DOMAIN environment variables."
  echo "Example:"
  echo "  export OKTA_API_TOKEN=\"your_okta_api_token\""
  echo "  export OKTA_DOMAIN=\"your_okta_domain\"  # e.g., dev-123456.okta.com"
  exit 1
fi

####################################
# Configuration
####################################
# Define your resource names and locations.
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
APP_NAME="woa-prod-app"
STATIC_WEB_APP_NAME="woa-prod-spa"
STATIC_WEB_APP_SKU="Standard"
LOG_ANALYTICS_NAME="woa-prod-logs"

# Retrieve GitHub information from your local git remote.
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
  echo "Ensure your network infrastructure is deployed first."
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
# Create or Recreate Okta OIDC Application Integration
####################################
# If OKTA_CLIENT_SECRET is not provided, then force recreate the integration to capture a new secret.
if [ -z "$OKTA_CLIENT_SECRET" ]; then
  echo "OKTA_CLIENT_SECRET not set. Forcing recreation of Okta integration..."
  # Query for any existing integration with the desired label.
  EXISTING_OKTA=$(curl -s -X GET "https://${OKTA_DOMAIN}/api/v1/apps?q=Azure%20Static%20Web%20App%20Auth" \
    -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
    -H "Accept: application/json")
  EXISTING_COUNT=$(echo "$EXISTING_OKTA" | jq 'length')
  if [ "$EXISTING_COUNT" -gt 0 ]; then
    echo "Existing Okta integrations found. Deleting them to force recreation..."
    # Loop over all found integrations and delete them (after deactivating if necessary).
    for APP_ID in $(echo "$EXISTING_OKTA" | jq -r '.[].id'); do
      echo "Deactivating integration $APP_ID..."
      curl -s -X POST "https://${OKTA_DOMAIN}/api/v1/apps/${APP_ID}/lifecycle/deactivate" \
        -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
        -H "Accept: application/json" > /dev/null
      echo "Deleting integration $APP_ID..."
      curl -s -X DELETE "https://${OKTA_DOMAIN}/api/v1/apps/${APP_ID}" \
        -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
        -H "Accept: application/json" > /dev/null
      echo "Deleted integration $APP_ID."
    done
  fi
  echo "Creating new Okta OIDC integration..."
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
else
  echo "Using existing Okta integration from environment variables."
fi

####################################
# Generate staticwebapp.config.json
####################################
echo "Generating staticwebapp.config.json with custom authentication settings..."
CONFIG_FILE="staticwebapp.config.json"
cat <<EOF > $CONFIG_FILE
{
  "routes": [
    {
      "route": "/*",
      "allowedRoles": ["authenticated"]
    }
  ],
  "auth": {
    "identityProviders": {
      "customOpenIdConnectProviders": {
        "okta": {
          "registration": {
            "clientIdSettingName": "OKTA_CLIENT_ID",
            "clientCredential": {
              "clientSecretSettingName": "OKTA_CLIENT_SECRET"
            },
            "openIdConnectConfiguration": {
              "wellKnownOpenIdConfiguration": "https://${OKTA_DOMAIN}/.well-known/openid-configuration"
            }
          },
          "login": {
            "nameClaimType": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
          }
        }
      }
    }
  }
}
EOF

####################################
# Auto-commit All Local Files and Force Push to main
####################################
echo "Auto-committing all local changes..."
git add -A
if ! git diff-index --quiet HEAD; then
  git commit -m "Auto commit from infra script"
fi
echo "Pulling latest changes (using rebase and autostash)..."
git pull --rebase --autostash || true
echo "Force pushing local changes to main..."
git push --force

####################################
# Configure Diagnostics (Monitoring)
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
  --metrics '[{"category": "AllMetrics","enabled": true,"retentionPolicy": {"days": 0,"enabled": false}}]' \
  --output none

####################################
# Set GitHub Deployment Token
####################################
echo "Setting up GitHub deployment token..."
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name "$STATIC_WEB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "properties.apiKey" -o tsv)
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --body "$DEPLOYMENT_TOKEN" \
  --repo "$GITHUB_ORG/$GITHUB_REPO"

####################################
# Output Important Information
####################################
echo "Retrieving deployment information..."
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
