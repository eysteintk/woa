#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Deploys your Next.js/TypeScript SPA to Azure Static Web Apps,
  auto-builds the app, and then auto-commits all local files (assumed to be truth) to GitHub.

  It also obtains a deployment token from Azure SWA, deploys to a preview environment,
  and outputs the deployment URL.

  Additionally, it supports promoting a preview environment to production.

.NOTES
  Ensure you’re logged in to Azure (az login) and GitHub (gh auth login).
  Make sure that your repository contains a valid GitHub Action workflow file (in .github/workflows)
  and that your local files are always correct.

  Also ensure you have installed Node.js, Next.js, and jq.
#>

#############################################################################
# CONFIGURATION
#############################################################################
$RESOURCE_GROUP = "abs-rg-we-prod"
$STATIC_WEB_APP_NAME = "woa-prod-spa"
$DIST_FOLDER = ".next"
$PREVIEW_PREFIX = "preview"
$NEXT_CACHE_DIR = ".next/cache"
$Env:AZURE_CORE_OUTPUT_PAGER = ""  # Disable paging

# Ensure output encoding is UTF8 so emojis show correctly
$OutputEncoding = [System.Text.UTF8Encoding]::new()

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
# AUTO-COMMIT AND PUSH FUNCTIONS
#############################################################################
function Commit-AndPush {
    Write-Host "🔄 Auto-committing all local changes..."
    # Add all changes
    git add -A
    # Check if there are changes to commit
    git diff-index --quiet HEAD
    if ($LASTEXITCODE -ne 0) {
        git commit -m "Auto commit from deploy script"
    } else {
        Write-Host "✅ No changes to commit."
    }
    Write-Host "🔄 Pulling latest changes with rebase and autostash..."
    git pull --rebase --autostash
    Write-Host "🔄 Force pushing local changes to main..."
    git push --force
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

    # Check for node_modules; install if missing or if package-lock changed.
    if (-not (Test-Path "node_modules")) {
        Write-Host "📦 Installing dependencies (node_modules missing)..."
        npm install --prefer-offline --no-audit --no-fund
    }
    elseif (-not (Test-Path ".last-package-lock.json") -or
            (-not (Compare-Object (Get-Content "package-lock.json") (Get-Content ".last-package-lock.json")))) {
        Write-Host "📦 package-lock.json changed, updating dependencies..."
        npm install --prefer-offline --no-audit --no-fund
        Copy-Item "package-lock.json" ".last-package-lock.json" -Force
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

        Start-Sleep -Seconds 10

        Write-Host "Fetching deployment URL..."
        $deploymentUrl = az staticwebapp show `
            --name $STATIC_WEB_APP_NAME `
            --resource-group $RESOURCE_GROUP `
            --query "defaultHostname" -o tsv

        if ([string]::IsNullOrEmpty($deploymentUrl)) {
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
    Print-Success "Environment '$previewName' promoted to production!"
}

#############################################################################
# MAIN
#############################################################################
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

# Auto-commit all local changes and force-push to main
Write-Host "`n🔄 Auto-committing all local changes..."
git add -A
git diff-index --quiet HEAD
if ($LASTEXITCODE -ne 0) {
    git commit -m "Auto commit from deploy script"
} else {
    Write-Host "✅ No changes to commit."
}
Write-Host "🔄 Pulling latest changes with rebase and autostash..."
git pull --rebase --autostash | Out-Null
Write-Host "🔄 Force pushing local changes to main..."
git push --force

End-Timing
