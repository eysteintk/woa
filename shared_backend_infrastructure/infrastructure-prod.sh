#!/bin/bash
# Consolidated Infrastructure Script for Azure Production Environment
set -e

################################################################################
# COLOR-CODED PRINT FUNCTIONS
################################################################################
function print_step() {
    echo -e "🔄 $1..."
}

function print_success() {
    echo -e "✅ $1"
}

function print_warning() {
    echo -e "⚠️  $1"
}

function print_error() {
    echo -e "❌ $1"
    exit 1
}

################################################################################
# CONFIGURATION
################################################################################
RESOURCE_GROUP="abs-rg-we-prod"
LOCATION="westeurope"

VNET_NAME="abs-vnet-we-prod"
PE_SUBNET="woa-private-endpoints"
PE_SUBNET_PREFIX="10.0.0.96/27"     # 10.0.0.0 - 10.0.0.31
CONTAINER_SUBNET="container-subnet"
CONTAINER_SUBNET_PREFIX="10.0.0.64/27"  # 10.0.0.64 - 10.0.0.95

PE_NSG="abs-nsg-woa-pe-we-prod"
CONTAINER_NSG="abs-nsg-container-we-prod"

LOG_ANALYTICS_NAME="woa-prod-logs"
REDIS_NAME="woa-prod-redis"
ACR_NAME="woaprodregistry"
CONTAINER_APP_ENV="woa-prod-env"

# Additional variables for Confluent
CONFLUENT_ORG_NAME="WoA"
ENVIRONMENT_NAME="prod"
CLUSTER_NAME="woa-prod"

# Storage account name for flow logs (must be globally unique, adjust as needed)
STORAGE_ACCOUNT="woaprodnetworklogs"

WEB_PUBSUB_NAME="woa-prod-pubsub"
WEB_PUBSUB_SKU="Standard_S1"
WEB_PUBSUB_HUB="woa"


################################################################################
# HELPER FUNCTIONS
################################################################################
function subnet_exists() {
    az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$1" &>/dev/null
}

function nsg_exists() {
    az network nsg show --name "$1" --resource-group "$RESOURCE_GROUP" &>/dev/null
}

function ensure_nsg() {
    local nsg_name="$1"
    local location="$2"
    if nsg_exists "$nsg_name"; then
        print_success "NSG '$nsg_name' exists"
    else
        print_step "Creating NSG '$nsg_name'"
        az network nsg create --name "$nsg_name" --resource-group "$RESOURCE_GROUP" --location "$location" --output none
        print_success "NSG '$nsg_name' created"
    fi
}

function ensure_subnet() {
    local subnet_name="$1"
    local address_prefix="$2"
    local nsg_name="$3"
    shift 3
    local extra_params="$@"

    if subnet_exists "$subnet_name"; then
        print_success "Subnet '$subnet_name' exists"
        return 0
    fi

    print_step "Creating subnet '$subnet_name'"
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$subnet_name" \
        --address-prefixes "$address_prefix" \
        --network-security-group "$nsg_name" \
        $extra_params \
        --output none
    print_success "Subnet '$subnet_name' created"
}

# Create or update an NSG rule (used for container NSG advanced rules)
function create_or_update_nsg_rule() {
    local nsg_name="$1"
    local rule_name="$2"
    local priority="$3"
    local direction="$4"
    local source_addrs="$5"
    local dest_addrs="$6"
    local dest_ports="$7"
    local protocol="$8"
    local access="$9"
    local description="${10}"

    if az network nsg rule show --name "$rule_name" --nsg-name "$nsg_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "NSG rule '$rule_name' exists in '$nsg_name'"
    else
        print_step "Creating NSG rule '$rule_name' in '$nsg_name'"
        az network nsg rule create \
            --name "$rule_name" \
            --nsg-name "$nsg_name" \
            --resource-group "$RESOURCE_GROUP" \
            --priority "$priority" \
            --direction "$direction" \
            --source-address-prefixes "$source_addrs" \
            --source-port-ranges "*" \
            --destination-address-prefixes "$dest_addrs" \
            --destination-port-ranges "$dest_ports" \
            --protocol "$protocol" \
            --access "$access" \
            --description "$description" \
            --output none
        print_success "NSG rule '$rule_name' created"
    fi
}

################################################################################
# 1. RESOURCE GROUP
################################################################################
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    print_step "Creating resource group '$RESOURCE_GROUP'"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    print_success "Resource group created"
else
    print_success "Resource group '$RESOURCE_GROUP' exists"
fi

################################################################################
# 2. LOG ANALYTICS WORKSPACE
################################################################################
if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_NAME" &>/dev/null; then
    print_step "Creating Log Analytics workspace '$LOG_ANALYTICS_NAME'"
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --output none
    print_success "Log Analytics workspace created"
else
    print_success "Log Analytics workspace '$LOG_ANALYTICS_NAME' exists"
fi

# Grab the workspace resource ID (for diagnosing resources) and customer ID (for container apps)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query id -o tsv)

WORKSPACE_CUSTOMER_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query customerId -o tsv)

WORKSPACE_SHARED_KEY=$(az monitor log-analytics workspace get-shared-keys \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query primarySharedKey -o tsv)

################################################################################
# 3. VIRTUAL NETWORK
################################################################################
if ! az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
    print_step "Creating VNET '$VNET_NAME'"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --location "$LOCATION" \
        --address-prefixes 10.0.0.0/16 \
        --output none
    print_success "VNET created"
else
    print_success "VNET '$VNET_NAME' exists"
fi

VNET_ID=$(az network vnet show -g "$RESOURCE_GROUP" -n "$VNET_NAME" --query id -o tsv)

################################################################################
# 4. VNET DIAGNOSTICS
################################################################################
print_step "Configuring VNET diagnostics"
az monitor diagnostic-settings create \
    --name "${VNET_NAME}-diagnostics" \
    --resource "$VNET_ID" \
    --workspace "$WORKSPACE_ID" \
    --metrics '[{"category":"AllMetrics","enabled":true}]' \
    --logs '[{"category":"VMProtectionAlerts","enabled":true}]' \
    --output none
print_success "VNET diagnostics configured"

################################################################################
# 5. NSGs (PRIVATE ENDPOINTS & CONTAINER APPS)
################################################################################
################################################################################
# NSG RULES CONFIGURATION
################################################################################
function ensure_nsg_rule() {
    local nsg_name="$1"
    local rule_name="$2"
    local priority="$3"
    local direction="$4"
    local source_addrs="$5"
    local dest_addrs="$6"
    local dest_ports="$7"
    local protocol="$8"
    local access="$9"
    local description="${10}"

    if az network nsg rule show --name "$rule_name" --nsg-name "$nsg_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        print_success "NSG rule '$rule_name' exists in '$nsg_name'"
    else
        print_step "Creating NSG rule '$rule_name' in '$nsg_name'"
        az network nsg rule create \
            --name "$rule_name" \
            --nsg-name "$nsg_name" \
            --resource-group "$RESOURCE_GROUP" \
            --priority "$priority" \
            --direction "$direction" \
            --source-address-prefixes "$source_addrs" \
            --source-port-ranges "*" \
            --destination-address-prefixes "$dest_addrs" \
            --destination-port-ranges "$dest_ports" \
            --protocol "$protocol" \
            --access "$access" \
            --description "$description" \
            --output none
        print_success "NSG rule '$rule_name' created"
    fi
}

# --- Configure PE NSG rules ---
print_step "Configuring rules for NSG '$PE_NSG'"

if ! az network nsg rule show --name "AllowVNetTraffic" --nsg-name "$PE_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$PE_NSG" \
        "AllowVNetTraffic" \
        100 \
        "Inbound" \
        "VirtualNetwork" \
        "VirtualNetwork" \
        "*" \
        "*" \
        "Allow" \
        "Allow VNet traffic"
fi

if ! az network nsg rule show --name "AllowPrivateEndpointsTraffic" --nsg-name "$PE_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$PE_NSG" \
        "AllowPrivateEndpointsTraffic" \
        110 \
        "Inbound" \
        "VirtualNetwork" \
        "*" \
        "*" \
        "*" \
        "Allow" \
        "Allow private endpoint connections"
fi

if ! az network nsg rule show --name "DenyAllInbound" --nsg-name "$PE_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$PE_NSG" \
        "DenyAllInbound" \
        4096 \
        "Inbound" \
        "*" \
        "*" \
        "*" \
        "*" \
        "Deny" \
        "Deny all inbound traffic"
fi

print_success "PE NSG rules configured"

# --- Configure Container NSG rules ---
print_step "Configuring rules for NSG '$CONTAINER_NSG'"

# Container Apps Management
if ! az network nsg rule show --name "AllowContainerAppsManagement" --nsg-name "$CONTAINER_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$CONTAINER_NSG" \
        "AllowContainerAppsManagement" \
        100 \
        "Inbound" \
        "AzureCloud" \
        "*" \
        "80 443 8080 8081 10250 10251 10252" \
        "Tcp" \
        "Allow" \
        "Allow Container Apps Management Traffic"
fi

# Databricks Outbound
if ! az network nsg rule show --name "AllowDatabricksOutbound" --nsg-name "$CONTAINER_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$CONTAINER_NSG" \
        "AllowDatabricksOutbound" \
        120 \
        "Inbound" \
        "VirtualNetwork" \
        "*" \
        "*" \
        "*" \
        "Allow" \
        "Allow Databricks Outbound Traffic"
fi

# Load Balancer
if ! az network nsg rule show --name "AllowLoadBalancer" --nsg-name "$CONTAINER_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$CONTAINER_NSG" \
        "AllowLoadBalancer" \
        200 \
        "Inbound" \
        "AzureLoadBalancer" \
        "*" \
        "*" \
        "*" \
        "Allow" \
        "Allow Azure Load Balancer"
fi

# VNet traffic inbound
if ! az network nsg rule show --name "AllowVnetInbound" --nsg-name "$CONTAINER_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$CONTAINER_NSG" \
        "AllowVnetInbound" \
        400 \
        "Inbound" \
        "VirtualNetwork" \
        "*" \
        "*" \
        "*" \
        "Allow" \
        "Allow inbound from VNet"
fi

# Internet outbound
if ! az network nsg rule show --name "AllowInternetOutbound" --nsg-name "$CONTAINER_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$CONTAINER_NSG" \
        "AllowInternetOutbound" \
        500 \
        "Outbound" \
        "VirtualNetwork" \
        "Internet" \
        "*" \
        "*" \
        "Allow" \
        "Allow outbound internet"
fi

# Deny all Internet inbound
if ! az network nsg rule show --name "DenyInternetInbound" --nsg-name "$CONTAINER_NSG" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    ensure_nsg_rule \
        "$CONTAINER_NSG" \
        "DenyInternetInbound" \
        4096 \
        "Inbound" \
        "Internet" \
        "*" \
        "*" \
        "*" \
        "Deny" \
        "Deny internet inbound"
fi

print_success "Container NSG rules configured"

################################################################################
# 6. CREATE SUBNETS
################################################################################
ensure_subnet "$PE_SUBNET" "$PE_SUBNET_PREFIX" "$PE_NSG" "--private-endpoint-network-policies Disabled"
ensure_subnet "$CONTAINER_SUBNET" "$CONTAINER_SUBNET_PREFIX" "$CONTAINER_NSG" \
    "--service-endpoints Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.App" \
    "--delegations Microsoft.App/environments"

################################################################################
# 7. CREATE AZURE CACHE FOR REDIS
################################################################################
if ! az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    print_step "Creating Azure Redis Cache '$REDIS_NAME'"
    az redis create \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --vm-size C4 \
        --minimum-tls-version "1.2" \
        --redis-version "6.0" \
        --tags Environment=Production Service=WebApp \
        --output none
    print_success "Azure Redis Cache created"

    # After creation, update network rules to disable public access
    print_step "Disabling public network access for Redis"
    az redis firewall-rules create \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --rule-name "AllowPrivateEndpoint" \
        --start-ip "10.0.0.0" \
        --end-ip "10.255.255.255" \
        --output none

    # Remove any existing firewall rule that allows public access
    az redis firewall-rules delete \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --rule-name "AllowAllPublicAccess" \
        --output none || true  # Ignore if rule doesn't exist

    print_success "Public network access effectively disabled for Redis"

    print_step "Configuring Redis private endpoint"
    az network private-endpoint create \
        --name "${REDIS_NAME}-endpoint" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --subnet "$PE_SUBNET" \
        --private-connection-resource-id $(az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv) \
        --group-id redisCache \
        --connection-name "${REDIS_NAME}-connection" \
        --output none
    print_success "Redis private endpoint configured"
else
    print_success "Azure Redis Cache '$REDIS_NAME' already exists"
fi

# Always ensure keyspace notifications are enabled
print_step "Enabling Redis keyspace notifications (KEA)"
az redis update \
    --name "$REDIS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --set redisConfiguration='{"notify-keyspace-events":"KEA"}' \
    --output none
print_success "Redis keyspace notifications enabled"

# Configure Redis diagnostics
print_step "Configuring Redis diagnostics settings"
az monitor diagnostic-settings create \
    --name "${REDIS_NAME}-diagnostics" \
    --resource $(az redis show -n "$REDIS_NAME" -g "$RESOURCE_GROUP" --query id -o tsv) \
    --workspace "$WORKSPACE_ID" \
    --logs '[{"category":"ConnectedClientList","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]' \
    --output none
print_success "Redis diagnostics configured"

################################################################################
# Private DNS Zone Configuration for Redis
################################################################################
print_step "Configuring Private DNS Zone for Redis"

# Create Private DNS Zone for Redis if it doesn't exist
if ! az network private-dns zone show \
    --resource-group "$RESOURCE_GROUP" \
    --name "privatelink.redis.cache.windows.net" &>/dev/null; then
    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP" \
        --name "privatelink.redis.cache.windows.net" \
        --output none
    print_success "Private DNS Zone for Redis created"
fi

# Link Private DNS Zone to VNet
if ! az network private-dns link vnet show \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "privatelink.redis.cache.windows.net" \
    --name "${VNET_NAME}-redis-dns-link" &>/dev/null; then
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "privatelink.redis.cache.windows.net" \
        --name "${VNET_NAME}-redis-dns-link" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false \
        --output none
    print_success "Private DNS Zone linked to VNet"
fi

# Create A record for Redis private endpoint
REDIS_PRIVATE_IP=$(az network private-endpoint show \
    --name "${REDIS_NAME}-endpoint" \
    --resource-group "$RESOURCE_GROUP" \
    --query 'networkInterfaces[0].id' -o tsv | \
    xargs -I {} az network nic show --ids {} --query 'ipConfigurations[0].privateIPAddress' -o tsv)

# Check if A record already exists
if ! az network private-dns record-set a show \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "privatelink.redis.cache.windows.net" \
    --name "$REDIS_NAME" &>/dev/null; then
    az network private-dns record-set a add-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "privatelink.redis.cache.windows.net" \
        --record-set-name "$REDIS_NAME" \
        --ipv4-address "$REDIS_PRIVATE_IP" \
        --output none
    print_success "A record created for Redis in Private DNS Zone"
fi

print_success "Redis Private DNS configuration completed"

################################################################################
# AZURE WEB PUBSUB SERVICE
################################################################################
print_step "Ensuring Azure Web PubSub service exists"
if ! az webpubsub show --name "$WEB_PUBSUB_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    print_step "Creating Azure Web PubSub service '$WEB_PUBSUB_NAME'"
    az webpubsub create \
        --name "$WEB_PUBSUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$WEB_PUBSUB_SKU" \
        --unit-count 1 \
        --tags Environment=Production Service=WebApp \
        --output none

    # disable public netowrk access
    az resource update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEB_PUBSUB_NAME" \
        --resource-type "Microsoft.SignalRService/WebPubSub" \
        --set properties.publicNetworkAccess="Disabled"
    print_success "Web PubSub service created"
else
    print_success "Web PubSub service '$WEB_PUBSUB_NAME' exists"
fi

print_step "Ensuring Web PubSub hub '$WEB_PUBSUB_HUB' exists"
HUB_EXISTS=$(az webpubsub hub list \
    --name "$WEB_PUBSUB_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$WEB_PUBSUB_HUB'].name" \
    --output tsv)

if [ -z "$HUB_EXISTS" ]; then
    print_step "Creating Web PubSub hub '$WEB_PUBSUB_HUB'"
    az webpubsub hub create \
    --name "$WEB_PUBSUB_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --hub-name "$WEB_PUBSUB_HUB" \
    --output none

    print_success "Web PubSub hub created"
else
    print_success "Web PubSub hub '$WEB_PUBSUB_HUB' exists"
fi

print_step "Ensuring Private DNS Zone exists for Web PubSub"
if ! az network private-dns zone show \
    --resource-group "$RESOURCE_GROUP" \
    --name "privatelink.webpubsub.azure.com" &>/dev/null; then

    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP" \
        --name "privatelink.webpubsub.azure.com" \
        --output none
    print_success "Private DNS Zone created"

    print_step "Creating Private DNS Zone VNet link"
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "privatelink.webpubsub.azure.com" \
        --name "${VNET_NAME}-webpubsub-dns-link" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false \
        --output none
    print_success "Private DNS Zone linked to VNet"
else
    print_success "Private DNS Zone exists"
fi

print_step "Ensuring Private Endpoint exists for Web PubSub"
if ! az network private-endpoint show \
    --name "${WEB_PUBSUB_NAME}-endpoint" \
    --resource-group "$RESOURCE_GROUP" &>/dev/null; then

    WEB_PUBSUB_ID=$(az webpubsub show \
        --name "$WEB_PUBSUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)

    az network private-endpoint create \
        --name "${WEB_PUBSUB_NAME}-endpoint" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --subnet "$PE_SUBNET" \
        --private-connection-resource-id "$WEB_PUBSUB_ID" \
        --group-id "webpubsub" \
        --connection-name "${WEB_PUBSUB_NAME}-connection" \
        --output none
    echo "✅ Private Endpoint created"
else
    echo "✅ Private Endpoint exists"
fi

print_step "Ensuring diagnostic settings exist for Web PubSub"
WEB_PUBSUB_ID=$(az webpubsub show \
    --name "$WEB_PUBSUB_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)

az monitor diagnostic-settings create \
    --name "${WEB_PUBSUB_NAME}-diagnostics" \
    --resource "$WEB_PUBSUB_ID" \
    --workspace "$WORKSPACE_ID" \
    --logs '[
        {
            "category": "ConnectivityLogs",
            "enabled": true
        },
        {
            "category": "MessagingLogs",
            "enabled": true
        },
        {
            "category": "HttpRequestLogs",
            "enabled": false
        }
    ]' \
    --metrics '[{
        "category": "AllMetrics",
        "enabled": true
    }]' \
    --output none

echo "Configuring network rules for Azure Web PubSub..."
az webpubsub network-rule update \
    --name $WEB_PUBSUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --public-network false \
    --connection-name "${WEB_PUBSUB_NAME}-connection" \
    --allow ServerConnection ClientConnection RESTAPI \
    --output none


print_success "Web PubSub configuration completed"


################################################################################
# 8. CREATE & CONFIGURE AZURE CONTAINER REGISTRY (ACR)
################################################################################
if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    print_step "Creating Azure Container Registry '$ACR_NAME'"
    az acr create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACR_NAME" \
        --sku Premium \
        --admin-enabled true \
        --location "$LOCATION" \
        --public-network-enabled false \
        --zone-redundancy enabled \
        --tags "Environment=Production" "Service=ContainerRegistry" \
        --output none
    print_success "Azure Container Registry created"

    print_step "Configuring ACR private endpoint"
    az network private-endpoint create \
        --name "${ACR_NAME}-endpoint" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --subnet "$PE_SUBNET" \
        --private-connection-resource-id $(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv) \
        --group-id registry \
        --connection-name "${ACR_NAME}-connection" \
        --output none
    print_success "ACR private endpoint configured"
else
    print_success "Azure Container Registry '$ACR_NAME' already exists"
fi

print_step "Configuring ACR diagnostics"
az monitor diagnostic-settings create \
    --name "${ACR_NAME}-diagnostics" \
    --resource $(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv) \
    --workspace "$WORKSPACE_ID" \
    --logs '[
        {"category": "ContainerRegistryRepositoryEvents","enabled": true},
        {"category": "ContainerRegistryLoginEvents","enabled": true}
    ]' \
    --metrics '[{"category": "AllMetrics","enabled":true}]' \
    --output none
print_success "ACR diagnostics configured"

################################################################################
# 9. CREATE OR USE EXISTING CONTAINER APPS ENVIRONMENT
################################################################################
print_step "Checking for existing Container Apps Environment using '$CONTAINER_SUBNET' subnet"
SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$CONTAINER_SUBNET" \
    --query id -o tsv)

existing_env_on_subnet=$(az containerapp env list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?properties.vnetConfiguration.infrastructureSubnetId=='${SUBNET_ID}'].name" -o tsv)

if [ -n "$existing_env_on_subnet" ]; then
    print_success "Found existing Container Apps Environment '$existing_env_on_subnet' on subnet"
    CONTAINER_APP_ENV="$existing_env_on_subnet"
else
    print_step "Creating new Container Apps Environment '$CONTAINER_APP_ENV'"
    az containerapp env create \
        --name "$CONTAINER_APP_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --infrastructure-subnet-resource-id "$SUBNET_ID" \
        --logs-destination log-analytics \
        --logs-workspace-id "$WORKSPACE_CUSTOMER_ID" \
        --logs-workspace-key "$WORKSPACE_SHARED_KEY" \
        --internal-only true \
        --output none
    print_success "Container Apps Environment '$CONTAINER_APP_ENV' created"
fi

################################################################################
# 10. CONFLUENT CLOUD SETUP (OPTIONAL)
################################################################################
print_step "Checking for existing Confluent organization '$CONFLUENT_ORG_NAME'"

# az confluent commands require the Confluent extension.
# Install if not present: az extension add --name confluent

existing_org=$(az confluent organization list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$CONFLUENT_ORG_NAME'].id" -o tsv)

if [ -z "$existing_org" ]; then
    print_step "Creating Confluent Cloud organization '$CONFLUENT_ORG_NAME'"
    az confluent organization create \
        --location "$LOCATION" \
        --name "$CONFLUENT_ORG_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --offer-id "confluent-cloud-azure-prod" \
        --plan-id "confluent-cloud-azure-payg-prod-3" \
        --plan-name "Pay-As-You-Go" \
        --publisher-id "confluentinc" \
        --term-unit "P1M" \
        --output none
    print_success "Confluent Cloud organization created"
else
    print_success "Confluent organization '$CONFLUENT_ORG_NAME' already exists"
fi

# The following commands assume you have the Confluent CLI installed and have
# the 'confluent' binary available. Adjust logic if using a different approach.

print_step "Attempting to retrieve and log in to Confluent organization"
CONFLUENT_ORG_ID=$(confluent organization list -o json | jq -r ".[] | select(.name == \"$CONFLUENT_ORG_NAME\") | .id")
if [ -z "$CONFLUENT_ORG_ID" ]; then
    print_warning "Could not find Confluent organization '$CONFLUENT_ORG_NAME' in the local 'confluent' CLI. Skipping local login..."
else
    if confluent login --no-browser --organization "$CONFLUENT_ORG_ID"; then
        print_success "Logged in to Confluent Cloud"
        print_step "Setting environment context to '$ENVIRONMENT_NAME'"
        ENV_ID=$(confluent environment list -o json | jq -r ".[] | select(.name == \"$ENVIRONMENT_NAME\") | .id")
        if [ -n "$ENV_ID" ]; then
            confluent environment use "$ENV_ID"
            print_success "Switched to Confluent environment '$ENVIRONMENT_NAME'"

            print_step "Checking for Kafka cluster '$CLUSTER_NAME'"
            if ! confluent kafka cluster list | grep -q "$CLUSTER_NAME"; then
                print_step "Creating Kafka cluster '$CLUSTER_NAME'"
                confluent kafka cluster create "$CLUSTER_NAME" \
                    --cloud azure \
                    --region westeurope \
                    --type basic \
                    --availability single-zone
                print_success "Confluent Kafka cluster created"
            else
                print_success "Kafka cluster '$CLUSTER_NAME' already exists"
            fi
        else
            print_warning "Environment '$ENVIRONMENT_NAME' not found in Confluent org"
        fi
    else
        print_warning "Failed to log in to Confluent Cloud CLI; skipping further Confluent setup"
    fi
fi

################################################################################
# 11. NETWORK MONITORING: FLOW LOGS / NETWORK WATCHER
################################################################################
print_step "Ensuring Network Watcher is enabled"
# NetworkWatcherRG is the default name for some Azure network watcher deployments
az network watcher configure \
    --resource-group "NetworkWatcherRG" \
    --locations "$LOCATION" \
    --enabled true \
    --output none
print_success "Network Watcher enabled"

# Create or ensure storage account for flow logs
print_step "Ensuring storage account '$STORAGE_ACCOUNT' exists for NSG flow logs"
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --min-tls-version TLS1_2 \
        --bypass AzureServices \
        --default-action Deny \
        --public-network-access Disabled \
        --allow-blob-public-access false \
        --output none
    print_success "Storage account '$STORAGE_ACCOUNT' created"
else
    print_success "Storage account '$STORAGE_ACCOUNT' already exists"
fi

# Enable Flow Logs for each NSG
for NSG in "$PE_NSG" "$CONTAINER_NSG"; do
    print_step "Setting up NSG flow logs for '$NSG'"
    az network watcher flow-log create \
        --location "$LOCATION" \
        --name "${NSG}-flowlog" \
        --nsg "$NSG" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --retention 90 \
        --workspace "$WORKSPACE_ID" \
        --enabled true \
        --output none
    print_success "Flow logs enabled for NSG '$NSG'"
done

################################################################################
# 12. FINAL OUTPUT
################################################################################
echo -e "\n✨ Infrastructure setup completed successfully! ✨"
echo "🔗 Resource Group: $RESOURCE_GROUP"
echo "🌐 Virtual Network: $VNET_NAME"
echo "📍 Subnets: $PE_SUBNET, $CONTAINER_SUBNET"
echo "📊 Log Analytics Workspace: $LOG_ANALYTICS_NAME"
echo "🔒 Redis Cache: $REDIS_NAME (Private Endpoint + Public Disabled)"
echo "🔌 Web PubSub: $WEB_PUBSUB_NAME (Private Endpoint + Hub: $WEB_PUBSUB_HUB)"
echo "🐳 Azure Container Registry: $ACR_NAME (Private Endpoint + Diagnostics)"
echo "🔄 Container Apps Environment: $CONTAINER_APP_ENV"
echo "☁️  Confluent Organization (optional): $CONFLUENT_ORG_NAME"
echo "🚀 Kafka Cluster (optional): $CLUSTER_NAME"
echo "📦 NSGs: $PE_NSG, $CONTAINER_NSG (Flow Logs enabled)"
echo "📥 Flow Logs Storage Account: $STORAGE_ACCOUNT"

echo -e "\nDeveloper/Deployment Tips:\n"
echo "1. For Container Apps, make sure you push your image to $ACR_NAME.azurecr.io"
echo "   and then deploy via az containerapp create \\"
echo "       --name <your-app-name> \\"
echo "       --resource-group $RESOURCE_GROUP \\"
echo "       --environment $CONTAINER_APP_ENV \\"
echo "       --image $ACR_NAME.azurecr.io/<repo>:<tag> \\"
echo "       --ingress 'internal' \\"
echo "       --registry-server $ACR_NAME.azurecr.io \\"
echo "       --registry-identity system \\"
echo
echo "2. For Confluent, ensure you have the 'confluent' CLI set up locally and an API key if needed."
echo "3. Ensure your DNS can resolve private endpoints (via Azure Private DNS + custom DNS, or similar)."
echo
print_success "All done!"
