#############################################################################
# CONFIGURATION
#############################################################################
$RESOURCE_GROUP = "abs-rg-we-prod"
$STATIC_WEB_APP_NAME = "woa-prod-spa"
$DIST_FOLDER = ".next"
$PREVIEW_PREFIX = "preview"
$NEXT_CACHE_DIR = ".next/cache"
$Env:AZURE_CORE_OUTPUT_PAGER = ""  # Disable paging

# Configure git to not prompt
$env:GIT_TERMINAL_PROMPT = 0
# Ensure git knows who we are (required for commits)
if (-not (git config --get user.email)) {
    git config --local user.email "azure-deployment@company.com"
    git config --local user.name "Azure Deployment"
}

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
# GITHUB SETUP
#############################################################################
function Get-GitHub-Info {
    $gitRemote = git config --get remote.origin.url
    if (-not $gitRemote) {
        Print-Error "No git remote found. Please initialize git repository first."
    }

    $GITHUB_ORG = $gitRemote -replace '.*github\.com[:/]([^/]+)/.*', '$1'
    $GITHUB_REPO = $gitRemote -replace '.*github\.com[:/][^/]+/(.*?)(.git)?$', '$1'

    return @{
        org = $GITHUB_ORG
        repo = $GITHUB_REPO
    }
}

function Setup-GitHub-Repository {
    Start-Step "Setting up GitHub repository"

    $gitInfo = Get-GitHub-Info
    $nodeVersion = (node --version).Trim('v')

    # Create GitHub workflow directory
    New-Item -Path ".github/workflows" -ItemType Directory -Force

    # Create workflow file
    $workflowContent = @"
name: Azure Static Web Apps Deployment
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    name: Deploy
    steps:
      - uses: actions/checkout@v3
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '$nodeVersion'
      - name: Build
        run: |
          npm install --prefer-offline --no-audit --no-fund
          cp -r .next/static .next/standalone/.next/
          cp -r public .next/standalone/
        env:
          NEXT_TELEMETRY_DISABLED: 1
      - name: Deploy
        uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: `${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          repo_token: `${{ secrets.GITHUB_TOKEN }}
          action: "upload"
          app_location: "/"
          output_location: ".next"
          skip_app_build: true
"@
    $workflowContent | Out-File -FilePath ".github/workflows/azure-static-web-apps.yml" -Encoding utf8 -Force

    # Set deployment token in GitHub secrets
    $deploymentToken = az staticwebapp secrets list `
        --name $STATIC_WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "properties.apiKey" -o tsv

    gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN --body "$deploymentToken" `
        --repo "$($gitInfo.org)/$($gitInfo.repo)"

    End-Step
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

    # Only clean if folder exists
    if (Test-Path $NEXT_CACHE_DIR) {
        Write-Host "Cleaning Next.js cache..."
        Remove-Item -Recurse -Force $NEXT_CACHE_DIR
    }

    Write-Host "Building Next.js application..."
    $Env:NEXT_TELEMETRY_DISABLED = 1
    npm install --prefer-offline --no-audit --no-fund
    npm run build

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

    Start-Step "Deploying to preview environment"

    # Build first
    Build-App

    # Generate environment name if not provided
    if (-not $customName) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $customName = "preview-$timestamp"
    }

    # Force add all changes and commit
    git add -A
    git commit -m "Preview deployment $customName" --allow-empty

    # Force push to main (non-interactive)
    git push -f origin main

    # Deploy using Azure CLI
    az staticwebapp deployment environment create `
        --name $STATIC_WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --environment-name $customName

    # Get Static Web App URLs
    $staticAppUrl = az staticwebapp show `
        --name $STATIC_WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "defaultHostname" -o tsv

    $previewUrl = "https://$customName.$staticAppUrl"

    End-Step
    Print-Success "Preview deployment complete"
    Write-Host "🌐 Preview URL: $previewUrl"
}

function Deploy-Production {
    Start-Step "Deploying to production"

    # Build first
    Build-App

    # Force add all changes and commit without prompting
    git add -A
    git commit -m "Production deployment $(Get-Date -Format 'yyyy-MM-dd HH:mm')" --allow-empty

    # Force push to main (non-interactive)
    git push -f origin main

    # Get Static Web App URL
    $staticAppUrl = az staticwebapp show `
        --name $STATIC_WEB_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "defaultHostname" -o tsv

    End-Step
    Print-Success "Production deployment initiated"
    Write-Host "🌐 Production URL: https://$staticAppUrl"
}

#############################################################################
# MAIN SCRIPT
#############################################################################
Start-Timing

# Process command line arguments
$cmd = if ($args.Count -eq 0) { "production" } else { $args[0] }

switch ($cmd) {
    "setup" {
        Setup-GitHub-Repository
    }
    "preview" {
        $customName = if ($args.Count -gt 1) { $args[1] } else { "" }
        Deploy-Preview $customName
    }
    "production" {
        Deploy-Production
    }
    default {
        Write-Host @"
Usage:
    $($MyInvocation.MyCommand.Name) [setup|preview|production]

    setup               Setup GitHub repository and workflow
    preview [name]      Deploy to preview environment
    production          Deploy to production environment
"@
        exit 1
    }
}

End-Timing