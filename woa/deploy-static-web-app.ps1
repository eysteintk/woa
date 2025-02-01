#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Deploys your dynamic Next.js TypeScript SPA to Azure Static Web Apps by
  auto-committing and force-pushing all local repository changes to the main branch.

  This script assumes:
    • Your infrastructure (Azure resources, Okta integration, etc.) has been provisioned already.
    • Your GitHub Actions workflow file (for Azure Static Web Apps CI/CD) is present in .github/workflows/
    • Your source code (including next.config.js for dynamic Next.js) is the truth.

  The push will trigger your GitHub Actions workflow to build and deploy your application.

.NOTES
  - Ensure you are logged in to Azure (az login) and GitHub (gh auth login).
  - Ensure you have the latest Azure CLI with the Static Web Apps extension and jq installed.
  - This script does not duplicate any infra provisioning or configuration file generation.
#>

#############################################################################
# Set UTF-8 Output Encoding and Console Code Page
#############################################################################
$OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 | Out-Null

#############################################################################
# CONFIGURATION
#############################################################################
# (These values are for reference; the infra script has already created your resources.)
$RESOURCE_GROUP = "abs-rg-we-prod"
$STATIC_WEB_APP_NAME = "woa-prod-spa"
# For dynamic Next.js, assume the repository root is your source folder.
$SOURCE_FOLDER = "."

#############################################################################
# UTILITY FUNCTIONS
#############################################################################
function Write-Step { Write-Host "[STEP] $args" }
function Write-Success { Write-Host "[SUCCESS] $args" }
function Write-ErrorAndExit { Write-Host "[ERROR] $args"; exit 1 }

#############################################################################
# TIMING FUNCTIONS
#############################################################################
$script:start_time = [int][double]::Parse((Get-Date -UFormat %s))
function End-Timing {
    $end_time = [int][double]::Parse((Get-Date -UFormat %s))
    $total_duration = $end_time - $script:start_time
    Write-Host "Total deployment time: ${total_duration}s"
}

#############################################################################
# AUTO-COMMIT AND PUSH FUNCTIONS
#############################################################################
function Commit-AndPush {
    Write-Step "Auto-committing all local changes..."
    git add -A
    if (-not (git diff-index --quiet HEAD)) {
        git commit -m "Auto commit from deployment script"
    } else {
        Write-Success "No changes to commit."
    }
    Write-Step "Pulling latest changes (rebase with autostash)..."
    git pull --rebase --autostash | Out-Null
    Write-Step "Force pushing local changes to main..."
    git push --force
}

#############################################################################
# MAIN DEPLOYMENT FLOW
#############################################################################
Write-Step "Starting deployment process..."
Commit-AndPush
Write-Success "Repository updated on GitHub. This should trigger the GitHub Actions workflow to build and deploy your dynamic Next.js SPA."
End-Timing
