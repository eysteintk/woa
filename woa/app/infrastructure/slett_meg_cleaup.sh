#!/bin/bash
# woa/app/infrastructure/cleanup-prod.sh
set -e

# Configuration
RESOURCE_GROUP="abs-rg-we-prod"
APP_NAME="woa-prod-app"
STATIC_WEB_APP_NAME="woa-prod-spa"

# Get GitHub information
GITHUB_ORG=$(git config --get remote.origin.url | sed -n 's/.*github\.com[:/]\([^/]*\)\/.*/\1/p')
GITHUB_REPO=$(git config --get remote.origin.url | sed -n 's/.*github\.com[:/][^/]*\/\(.*\)\.git/\1/p')

echo "🧹 Starting cleanup process..."

# Remove GitHub Secret
echo "Removing GitHub deployment token..."
gh secret remove AZURE_STATIC_WEB_APPS_API_TOKEN --repo "$GITHUB_ORG/$GITHUB_REPO"

# Delete Application Insights
echo "Deleting Application Insights..."
az monitor app-insights component delete \
    --app "${APP_NAME}-insights" \
    --resource-group $RESOURCE_GROUP \
    --yes \
    --output none

# Delete Static Web App
echo "Deleting Static Web App..."
az staticwebapp delete \
    --name $STATIC_WEB_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --yes \
    --output none

echo "
✅ Cleanup Complete! The following resources have been removed:
----------------------------------------------------------
- Static Web App ($STATIC_WEB_APP_NAME)
- Application Insights (${APP_NAME}-insights)
- GitHub Deployment Token
"