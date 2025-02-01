#!/usr/bin/env pwsh

#############################################################################
# CONFIGURATION
#############################################################################
$RESOURCE_GROUP = "abs-rg-we-prod"
$STATIC_WEB_APP_NAME = "woa-prod-spa"
$DIST_FOLDER = ".next"
$PREVIEW_PREFIX = "preview"
$NEXT_CACHE_DIR = ".next/cache"
$Env:AZURE_CORE_OUTPUT_PAGER = ""  # Disable paging

#############################################################################
# UTILITY FUNCTIONS
#############################################################################
function Print-Step { Write-Host "🔄 $args" }
function Print-Success { Write-Host "✅ $args" }
function Print-Error { Write-Host "❌ $args"; exit 1 }

#############################################################################
# TIMING FUNCTIONS
#############################################################################
$script:start_time = 0
$script:step_start_time = 0

function Start-Timing {
    $script:start_time = [int][double]::Parse((Get-Date -UFormat %s))
    $script:step_start_time = $script:start_time
    Write-Host "⏱️  Starting deployment at $(Get-Date)"
}

function Start-Step {
    param([string]$stepName)
    $script:step_start_time = [int][double]::Parse((Get-Date -UFormat %s))
    Write-Host "`n⏱️  Starting: $stepName"
}

function End-Step {
    $end_time = [int][double]::Parse((Get-Date -UFormat %s))
    $duration = $end_time - $script:step_start_time
    Write-Host "⏱️  Completed in ${duration}s"
}

function End-Timing {
    $end_time = [int][double]::Parse((Get-Date -UFormat %s))
    $total_duration = $end_time - $script:start_time
    Write-Host "`n⏱️  Total deployment time: ${total_duration}s"
}

#############################################################################
# USAGE HELPER
#############################################################################
function Show-Usage {
    Write-Host @"
Usage:
    $($MyInvocation.MyCommand.Name) preview [<customPreviewName>]
        Builds your static site and deploys it to a "preview" environment,
        either "preview-YYYYMMDD_HHMMSS" by default or a custom name if you pass one.

    $($MyInvocation.MyCommand.Name) promote <previewEnvironmentName>
        Promotes (swaps) an existing preview environment to production.

Examples:
    1) Deploy a new preview:
       ./deploy-static-web-app.ps1 preview
    2) Deploy a named preview:
       ./deploy-static-web-app.ps1 preview my-test
    3) Promote that environment to production:
       ./deploy-static-web-app.ps1 promote my-test
"@
}

#############################################################################
# BUILD FUNCTIONS
#############################################################################
function Check-Build-Folder {
    Print-Step "Checking if build folder exists"
    if (-not (Test-Path $DIST_FOLDER)) {
        Print-Error "Build folder not found: $DIST_FOLDER. Please run 'npm run build' first."
    }
    Print-Success "Build folder found: $DIST_FOLDER"
}

function Build-App {
    Start-Step "Building application"

    # Fast dependency check and install
    if (-not (Test-Path "node_modules")) {
        Write-Host "📦 Installing dependencies (node_modules missing)..."
        npm install --prefer-offline --no-audit --no-fund
    }
    elseif (-not (Test-Path ".last-package-lock.json") -or
            (-not (Compare-Object (Get-Content "package-lock.json") (Get-Content ".last-package-lock.json")))) {
        Write-Host "📦 package-lock.json changed, updating dependencies..."
        npm install --prefer-offline --no-audit --no-fund
        Copy-Item "package-lock.json" ".last-package-lock.json"
    }
    else {
        Write-Host "✅ Dependencies up to date, skipping install."
    }

    Write-Host "🏗️  Running next build..."
    $Env:NEXT_TELEMETRY_DISABLED = 1
    npx next build --no-lint

    if (-not (Test-Path $DIST_FOLDER)) {
        Print-Error "Build failed: Output folder '$DIST_FOLDER' not found after build"
    }

    End-Step
}

#############################################################################
# DEPLOYMENT FUNCTIONS
#############################################################################
function Deploy-Preview {
    param([string]$customName)

    Start-Step "Validating configuration"
    $swaConfigExists = Test-Path "swa-cli.config.json"
    if (-not $swaConfigExists) {
        Write-Host "Creating SWA CLI config..."
        swa init --app-location $DIST_FOLDER
    }
    End-Step

    Check-Build-Folder

    # Generate preview environment name
    if ($customName) {
        $stageName = $customName
    }
    else {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $stageName = "${PREVIEW_PREFIX}-${timestamp}"
    }

    Start-Step "Getting deployment token"
    $token = az staticwebapp secrets list `
        --name $STATIC_WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "properties.apiKey" -o tsv

    if ([string]::IsNullOrEmpty($token)) {
        Print-Error "Failed to retrieve deployment token. Ensure your Azure Static Web App exists."
    }

    End-Step

    Start-Step "Deploying to staging environment '$stageName'"

    try {
        Write-Host "Running SWA deployment command..."
        $deploymentResult = swa deploy `
            --app-location $DIST_FOLDER `
            --deployment-token $token `
            --env $stageName `
            --verbose

        Write-Host "Raw deployment output:"
        Write-Host $deploymentResult

        # Wait a moment for deployment to complete
        Start-Sleep -Seconds 10

        # Get the deployment URL from Azure
        Write-Host "Fetching deployment URL..."
        $deploymentUrl = az staticwebapp show `
            --name $STATIC_WEB_APP_NAME `
            --resource-group $RESOURCE_GROUP `
            --query "defaultHostname" -o tsv

        if ([string]::IsNullOrEmpty($deploymentUrl)) {
            Write-Host "Failed to get deployment URL from Azure CLI"
            Print-Error "Deployment may have failed. Check Azure portal for status."
        }

        End-Step

        Print-Success "Deployment to '$stageName' complete!"
        Write-Host "🌐 Preview URL: https://$deploymentUrl"
        Write-Host ""
        Write-Host "To promote this preview to production, run:"
        Write-Host "  ./deploy-static-web-app.ps1 promote $stageName"
    }
    catch {
        Write-Host "Error during deployment:"
        Write-Host $_
        Print-Error "Deployment failed with an error"
    }
}

function Promote-ToProduction {
    param([string]$previewName)

    if (-not $previewName) {
        Write-Host "❌ Please specify the preview environment name you want to promote."
        Show-Usage
        exit 1
    }

    Start-Step "Promoting '$previewName' to production"

    az staticwebapp environment swap `
        --name $STATIC_WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --source $previewName `
        --target "production"

    End-Step
    Print-Success "Environment '$previewName' was promoted to production!"
}

#############################################################################
# MAIN
#############################################################################

# Start timing the entire process
Start-Timing

# Process command line arguments
$cmd = if ($args.Count -eq 0 -or $args[0] -eq "preview") {
    "preview"
} else {
    $args[0]
}

switch ($cmd) {
    "preview" {
        $customName = if ($args.Count -gt 1) { $args[1] } else { "" }
        Build-App
        Deploy-Preview $customName
    }
    "promote" {
        if ($args.Count -lt 2) {
            Write-Host "❌ You must provide the preview environment name to promote."
            Show-Usage
            exit 1
        }
        Promote-ToProduction $args[1]
    }
    default {
        Show-Usage
        exit 1
    }
}

# End timing and show total
End-Timing