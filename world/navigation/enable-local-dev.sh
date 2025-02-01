#!/bin/bash
#
# enable-local-dev.sh
#
# Sets up Azure Bastion + Jumpbox for local development, ensuring Redis and
# other necessary resources are correctly accessible via SSH tunnels.
#

set -euo pipefail

###############################################################################
# 1. PRINT FUNCTIONS
###############################################################################
function print_step() {
    echo "🔄 $1..."
}

function print_success() {
    echo "✅ $1"
}

function print_warning() {
    echo "⚠️  $1"
}

function print_error() {
    echo "❌ $1"
    exit 1
}

function print_complete() {
    echo "✨ $1"
}

###############################################################################
# 2. CONFIGURATION
###############################################################################
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"
BASTION_NAME="woa-prod-bastion"
JUMPBOX_NAME="woa-prod-jumpbox"

REDIS_NAME="woa-prod-redis"
LOCAL_REDIS_PORT="6380"
LOCAL_SSH_PORT="2222"

ACR_NAME="woaprodregistry"
PUBSUB_NAME="woa-prod-pubsub"
PUBSUB_HUB="woa"

if grep -qi microsoft /proc/version 2>/dev/null; then
    SSH_KEY_DIR="$HOME/.ssh"
    SSH_KEY_BASENAME="$SSH_KEY_DIR/woa-prod-jumpbox-key"
else
    SSH_KEY_DIR="."
    SSH_KEY_BASENAME="woa-prod-jumpbox-key"
fi

###############################################################################
# 3. PREREQUISITES CHECK
###############################################################################
function check_prerequisites() {
    print_step "Checking required tools"
    local tools=("az" "ssh-keygen" "redis-cli" "nc")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            print_error "'$tool' is required but not installed."
        fi
    done

    if ! az account show &>/dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
    fi

    mkdir -p "$SSH_KEY_DIR"
    chmod 700 "$SSH_KEY_DIR"
}

###############################################################################
# 4. RETRIEVE RESOURCE INFO
###############################################################################
function get_redis_info() {
    local host port key
    host=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query hostName -o tsv)
    port=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query sslPort -o tsv)
    key=$(az redis list-keys --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query primaryKey -o tsv)

    printf "%s\n%s\n%s\n" "$host" "$port" "$key"
}

function get_jumpbox_ip() {
    print_step "Retrieving Jumpbox private IP"
    local ip
    ip=$(az vm list-ip-addresses --resource-group "$RESOURCE_GROUP" --name "$JUMPBOX_NAME" --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv | tr -d '[:space:]')
    echo "$ip"
}

###############################################################################
# 5. CREATE CONFIGURATION FILES
###############################################################################
function create_local_env() {
    local redis_host="$1"
    local redis_port="$2"
    local redis_key="$3"

    print_step "Creating local.env"

    local acr_username acr_password pubsub_conn
    acr_username=$(az acr credential show --name "$ACR_NAME" --query username -o tsv 2>/dev/null || print_error "Failed to get ACR username")
    acr_password=$(az acr credential show --name "$ACR_NAME" --query passwords[0].value -o tsv 2>/dev/null || print_error "Failed to get ACR password")
    pubsub_conn=$(az webpubsub key show --name "$PUBSUB_NAME" --resource-group "$RESOURCE_GROUP" --query primaryConnectionString -o tsv 2>/dev/null || print_error "Failed to get Web PubSub connection string")

    cat > local.env <<EOF
# Local environment configuration

# Redis configuration
REDIS_HOST=127.0.0.1
REDIS_PORT=$LOCAL_REDIS_PORT
REDIS_PASSWORD=$redis_key
REDIS_SSL=true

# Container Registry
ACR_SERVER=${ACR_NAME}.azurecr.io
ACR_USERNAME=$acr_username
ACR_PASSWORD=$acr_password

# Web PubSub
AZURE_WEBPUBSUB_CONNECTION_STRING=${pubsub_conn}
AZURE_WEBPUBSUB_HUB_NAME=${PUBSUB_HUB}

# SSH configuration
SSH_KEY_PATH=${SSH_KEY_BASENAME}
JUMPBOX_HOST=127.0.0.1
JUMPBOX_PORT=${LOCAL_SSH_PORT}
EOF

    chmod 600 local.env
    print_success "local.env created"
}

###############################################################################
# 6. START TUNNELS
###############################################################################
function start_bastion_tunnel() {
    local jumpbox_ip="$1"

    print_step "Starting Bastion tunnel"
    print_warning "Defined port is currently unavailable - this can be safely ignored if the tunnel is working."

    # Kill any existing tunnel processes
    if pgrep -f "az network bastion tunnel.*$LOCAL_SSH_PORT" >/dev/null; then
        print_warning "Existing tunnel found on port $LOCAL_SSH_PORT - cleaning up"
        pkill -f "az network bastion tunnel.*$LOCAL_SSH_PORT"
        sleep 2
    fi

    # Get subscription ID and create tunnel
    local subscription_id=$(az account show --query id -o tsv)
    az network bastion tunnel \
        --name "$BASTION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --target-resource-id "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${JUMPBOX_NAME}" \
        --resource-port 22 \
        --port "$LOCAL_SSH_PORT" &

    sleep 3

    if nc -z localhost "$LOCAL_SSH_PORT"; then
        print_success "Bastion tunnel established successfully"
        return 0
    fi

    print_error "Failed to establish Bastion tunnel"
}

function check_redis_connection() {
    local redis_key="$1"

    redis_response=$(redis-cli -p $LOCAL_REDIS_PORT --tls << EOF
AUTH $redis_key
PING
EOF
)
    if echo "$redis_response" | grep -q "PONG"; then
        print_success "Redis connection successful (PONG received)"
        return 0
    else
        return 1
    fi
}

function start_redis_tunnel() {
    local redis_host="$1"
    local redis_port="$2"
    local redis_key="$3"

    print_step "Checking Redis connection"

    # First check if Redis is already accessible
    if check_redis_connection "$redis_key"; then
        print_success "Redis connection already established"
        return 0
    fi

    # Only try to create tunnel if Redis isn't already accessible
    print_step "Starting Redis SSH tunnel"
    nohup ssh -i "$SSH_KEY_BASENAME" -p "$LOCAL_SSH_PORT" -L "$LOCAL_REDIS_PORT:$redis_host:$redis_port" -N azureuser@127.0.0.1 &>/dev/null &

    sleep 3
    if check_redis_connection "$redis_key"; then
        print_success "Redis tunnel established"
        return 0
    fi

    print_error "Failed to establish Redis connection"
}

###############################################################################
# 6.5 CHECK WEB PUBSUB CONNECTION
###############################################################################
function check_webpubsub_connection() {
    local pubsub_conn="$1"

    print_step "Checking Web PubSub connection"

    # Using curl to test Web PubSub connectivity
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: $pubsub_conn" "https://$PUBSUB_NAME.webpubsub.azure.com/api/health")

    if [[ "$response" == "200" ]]; then
        print_success "Web PubSub connection successful"
        return 0
    else
        print_error "Failed to connect to Azure Web PubSub (HTTP $response). Please check credentials and network."
    fi
}

###############################################################################
# 7. MAIN EXECUTION
###############################################################################
function main() {
    print_step "Starting Local Dev Environment Setup"

    check_prerequisites

    # Get resource information
    redis_host=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query hostName -o tsv)
    redis_port=$(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query sslPort -o tsv)
    redis_key=$(az redis list-keys --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query primaryKey -o tsv)
    jumpbox_ip=$(get_jumpbox_ip)

    # Retrieve Web PubSub Connection String separately
    pubsub_conn=$(az webpubsub key show --name "$PUBSUB_NAME" --resource-group "$RESOURCE_GROUP" --query primaryConnectionString -o tsv 2>/dev/null)

    # Create local.env
    create_local_env "$redis_host" "$redis_port" "$redis_key"

    # Start tunnels
    start_bastion_tunnel "$jumpbox_ip"
    start_redis_tunnel "$redis_host" "$redis_port" "$redis_key"

    # Check Web PubSub connectivity
    check_webpubsub_connection "$pubsub_conn"

    print_success "Local development environment is ready!"
    echo -e "\n✨ Summary:\n  - Redis: 127.0.0.1:$LOCAL_REDIS_PORT\n  - Jumpbox SSH: 127.0.0.1:$LOCAL_SSH_PORT\n  - Config: local.env created\n"
    echo -e "Note: To stop the tunnels, you can use: pkill -f 'az network bastion tunnel' && pkill -f 'ssh.*-L.*$LOCAL_REDIS_PORT'"
}

main