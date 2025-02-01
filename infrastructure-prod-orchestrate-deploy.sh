#!/bin/bash
# infrastructure-prod-orchestrate-deploy.sh
set -e

start_time=$(date +%s)

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ Required command '$1' not found."
        case "$1" in
            "az")
                echo "   To install Azure CLI, visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
                ;;
            "confluent")
                echo "   To install Confluent CLI, visit: https://docs.confluent.io/confluent-cli/current/install.html"
                ;;
            "jq")
                echo "   To install jq, run: sudo apt-get update && sudo apt-get install -y jq"
                ;;
            *)
                echo "   Please install this dependency before continuing."
                ;;
        esac
        return 1
    fi
}

# Function to check all required dependencies
check_dependencies() {
    echo "🔍 Checking required dependencies..."
    local missing_deps=0

    # List of required dependencies
    local deps=("az" "confluent" "jq")

    for dep in "${deps[@]}"; do
        echo -n "   Checking for $dep... "
        if check_command "$dep"; then
            echo "✅"
        else
            echo "❌"
            missing_deps=$((missing_deps + 1))
        fi
    done

    # Check Azure CLI login status
    echo -n "   Checking Azure CLI login status... "
    if az account show &>/dev/null; then
        echo "✅"
    else
        echo "❌"
        echo "   Please run 'az login' first"
        missing_deps=$((missing_deps + 1))
    fi

    # Check Confluent CLI login status
    echo -n "   Checking Confluent CLI login status... "
    if confluent kafka cluster list &>/dev/null; then
        echo "✅"
    else
        echo "❌"
        echo "   Please run 'confluent login --no-browser' first"
        missing_deps=$((missing_deps + 1))
    fi

    if [ $missing_deps -gt 0 ]; then
        echo "❌ Missing $missing_deps required dependencies. Please install them and try again."
        exit 1
    fi

    echo "✅ All dependencies satisfied!"
    echo ""
}

# Function to handle errors
handle_error() {
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    echo "❌ Error in deployment after ${elapsed} seconds"
    exit 1
}

trap 'handle_error' ERR

# Check dependencies before proceeding
check_dependencies

# Deployment flags
DEPLOY_SHARED_BACKEND=true       # Must be deployed first
DEPLOY_WEB=true                  # Must be deployed after shared backend
DEPLOY_SKILLS=false              # Must be deployed after web
DEPLOY_OPPONENTS=false
DEPLOY_PLAYERS=false
DEPLOY_WORLD=true               # New world domain deployment flag

echo "🚀 Starting deployment..."
echo "📋 Deployment plan:"
[[ $DEPLOY_SHARED_BACKEND == true ]] && echo "   ▫️ Shared Backend Infrastructure (includes Web PubSub)"
[[ $DEPLOY_WEB == true ]] && echo "   ▫️ Web Application (Static Web App + Front Door)"
[[ $DEPLOY_SKILLS == true ]] && echo "   ▫️ Skills Domain (Container Apps)"
[[ $DEPLOY_OPPONENTS == true ]] && echo "   ▫️ Opponents Domain"
[[ $DEPLOY_PLAYERS == true ]] && echo "   ▫️ Players Domain"
[[ $DEPLOY_WORLD == true ]] && echo "   ▫️ World Domain"
echo ""

# Create shared backend infrastructure (includes Web PubSub)
if [[ $DEPLOY_SHARED_BACKEND == true ]]; then
    echo "🔨 Creating shared backend infrastructure..."
    ./shared_backend_infrastructure/infrastructure-prod.sh
fi

# Deploy web application infrastructure
if [[ $DEPLOY_WEB == true ]]; then
    echo "🌐 Deploying web application infrastructure..."
    ./woa/app/infrastructure/infrastructure-prod.sh
fi

# Deploy domain infrastructure
if [[ $DEPLOY_SKILLS == true ]]; then
    echo "⚔️  Deploying skills infrastructure..."
    ./skill/infrastructure-prod.sh
fi

if [[ $DEPLOY_OPPONENTS == true ]]; then
    echo "👾 Deploying opponents infrastructure..."
    ./opponents/infrastructure-prod.sh
fi

if [[ $DEPLOY_PLAYERS == true ]]; then
    echo "👤 Deploying players infrastructure..."
    ./players/infrastructure-prod.sh
fi

if [[ $DEPLOY_WORLD == true ]]; then
    echo "🌍 Deploying world infrastructure..."
    ./world/infrastructure-prod.sh
fi

end_time=$(date +%s)
total_elapsed=$((end_time - start_time))

echo "✨ Deployment complete in ${total_elapsed} seconds!"
echo ""
echo "📊 Deployed resources:"
az resource list \
    --resource-group abs-rg-we-prod \
    --query "[?contains(name, 'woa-prod')].{name:name, type:type}" \
    --output table