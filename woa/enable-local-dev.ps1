#############################################################################
# ENABLE LOCAL DEVELOPMENT FOR STATIC WEB APP (PowerShell Version)
#############################################################################

param([switch]$Force)

# Utility functions for output messages
function Print-Step { Write-Host "🔄 $args"; }
function Print-Success { Write-Host "✅ $args"; }
function Print-Error { Write-Host "❌ $args"; exit 1; }

#############################################################################
# CHECK PREREQUISITES: Node, npm, Azure CLI, SWA CLI, GitHub CLI
#############################################################################
function Check-Prerequisites {
    Print-Step "Checking required tools"

    $tools = @("npm", "node", "swa", "az", "gh")

    foreach ($tool in $tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Print-Error "'$tool' is required but not installed. Please install it and try again."
        }
    }

    Print-Success "All required tools are installed"
}

#############################################################################
# CHECK IF AZURE CLI IS LOGGED IN
#############################################################################
function Check-Az-Login {
    Print-Step "Checking if Azure CLI is authenticated"

    $accountInfo = az account show --query "id" -o tsv 2>$null

    if ([string]::IsNullOrEmpty($accountInfo)) {
        Print-Error "Azure CLI is not authenticated. Please run 'az login' and try again."
    }

    Print-Success "Azure CLI is authenticated (Subscription ID: $accountInfo)"
}

#############################################################################
# CHECK IF GITHUB CLI IS AUTHENTICATED
#############################################################################
function Check-GitHub-Login {
    Print-Step "Checking if GitHub CLI is authenticated"

    $ghAuth = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Print-Error "GitHub CLI is not authenticated. Please run 'gh auth login' and try again."
    }

    Print-Success "GitHub CLI is authenticated"
}

#############################################################################
# CHECK IF SWA CLI IS LOGGED IN
#############################################################################
function Check-SWA-Login {
    Print-Step "Checking if SWA CLI is authenticated"

    $swaAuth = swa login 2>&1 | Out-String
    if ($swaAuth -match "Sign in") {
        Print-Error "SWA CLI is not authenticated. Please run 'swa login' and try again."
    }

    Print-Success "SWA CLI is authenticated"
}

#############################################################################
# RETRIEVE WEB PUBSUB CONNECTION STRING
#############################################################################
function Get-ConnectionString {
    Print-Step "Retrieving Web PubSub connection string"

    $CONNECTION_STRING = az webpubsub key show `
        --name "woa-prod-pubsub" `
        --resource-group "abs-rg-we-prod" `
        --query "primaryConnectionString" -o tsv 2>$null

    if ([string]::IsNullOrEmpty($CONNECTION_STRING)) {
        Print-Error "Failed to retrieve Web PubSub connection string."
    }

    Print-Success "Retrieved Web PubSub connection string"
    return $CONNECTION_STRING
}

#############################################################################
# VALIDATE CONNECTION STRING BY ATTEMPTING API CALL
#############################################################################
function Validate-ConnectionString {
    param([string]$ConnectionString)

    Print-Step "Validating Web PubSub connection string"

    $nodeModulesPath = Resolve-Path "$PSScriptRoot\node_modules"
    $env:NODE_PATH = "$nodeModulesPath"

    $testScript = "temp_connection_test.js"
    @"
const { WebPubSubServiceClient } = require("@azure/web-pubsub");

async function testConnection() {
    try {
        const serviceClient = new WebPubSubServiceClient("$ConnectionString", "woa");
        await serviceClient.getClientAccessToken();
        console.log("Connection successful");
        process.exit(0);
    } catch (error) {
        console.error("Connection failed:", error.message);
        process.exit(1);
    }
}

testConnection();
"@ | Out-File -Encoding utf8 $testScript

    $nodeResult = & node $testScript

    if ($LASTEXITCODE -eq 0) {
        Print-Success "Web PubSub connection verified successfully"
    } else {
        Print-Error "Failed to connect to Web PubSub"
    }

    Remove-Item -Force $testScript
}

#############################################################################
# CREATE .env.local FILE
#############################################################################
function Create-Env-File {
    Print-Step "Creating .env.local file"

    $CONNECTION_STRING = Get-ConnectionString
    Validate-ConnectionString -ConnectionString $CONNECTION_STRING

    @"
NEXT_PUBLIC_BASE_URL=http://localhost:3000
WEB_PUBSUB_CONNECTION_STRING=$CONNECTION_STRING
WEB_PUBSUB_HUB_NAME=woa
"@ | Out-File -Encoding utf8 .env.local

    Print-Success ".env.local file created successfully"
}

#############################################################################
# MAIN FUNCTION: RUN ALL SETUP STEPS
#############################################################################
function Main {
    Print-Step "Starting Frontend Local Dev Setup"
    Check-Prerequisites
    Check-Az-Login
    Check-SWA-Login
    Check-GitHub-Login
    Create-Env-File
    Print-Success "Frontend local development environment is ready!"
}

# Run the main function
Main