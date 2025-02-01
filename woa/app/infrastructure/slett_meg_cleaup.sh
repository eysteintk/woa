#!/bin/bash
# cleanup-okta.sh
set -e

# Ensure required Okta environment variables are set.
if [ -z "$OKTA_API_TOKEN" ] || [ -z "$OKTA_DOMAIN" ]; then
    echo "Error: Please set OKTA_API_TOKEN and OKTA_DOMAIN environment variables."
    echo "Example:"
    echo "  export OKTA_API_TOKEN=\"your_okta_api_token\""
    echo "  export OKTA_DOMAIN=\"your_okta_domain\"  # e.g., dev-123456.okta.com"
    exit 1
fi

echo "Searching for Okta integrations with label 'Azure Static Web App Auth'..."

# Query Okta for apps matching the label.
APPS=$(curl -s -X GET "https://${OKTA_DOMAIN}/api/v1/apps?q=Azure%20Static%20Web%20App%20Auth" \
  -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
  -H "Accept: application/json")

# Filter results for those whose label exactly matches "Azure Static Web App Auth".
APP_IDS=$(echo "$APPS" | jq -r '.[] | select(.label=="Azure Static Web App Auth") | .id')

if [ -z "$APP_IDS" ]; then
    echo "No Okta integrations with label 'Azure Static Web App Auth' found."
    exit 0
fi

echo "Found Okta integrations with IDs:"
echo "$APP_IDS"

for APP_ID in $APP_IDS; do
    echo "Deactivating Okta integration with ID: $APP_ID..."
    DEACTIVATE_RESPONSE=$(curl -s -X POST "https://${OKTA_DOMAIN}/api/v1/apps/${APP_ID}/lifecycle/deactivate" \
      -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
      -H "Accept: application/json")
    if [ -z "$DEACTIVATE_RESPONSE" ] || [ "$DEACTIVATE_RESPONSE" = "{}" ]; then
        echo "Integration with ID: $APP_ID deactivated successfully."
    else
        echo "Warning: Received response while deactivating integration with ID $APP_ID:"
        echo "$DEACTIVATE_RESPONSE"
    fi

    echo "Deleting Okta integration with ID: $APP_ID..."
    DELETE_RESPONSE=$(curl -s -X DELETE "https://${OKTA_DOMAIN}/api/v1/apps/${APP_ID}" \
      -H "Authorization: SSWS ${OKTA_API_TOKEN}" \
      -H "Accept: application/json")
    if echo "$DELETE_RESPONSE" | grep -qi "errorCode"; then
        echo "Error deleting integration with ID $APP_ID. Response:"
        echo "$DELETE_RESPONSE"
    else
        echo "Integration with ID $APP_ID deleted successfully."
    fi
done

echo "Okta integrations cleanup complete."
