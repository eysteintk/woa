#!/bin/bash

# Configuration
RESOURCE_GROUP="abs-rg-we-prod"
BASTION_NAME="woa-prod-bastion"
JUMPBOX_NAME="woa-prod-jumpbox"
USERNAME="azureuser"
SSH_KEY_BASENAME="$HOME/.ssh/woa-prod-jumpbox-key"

###############################################################################
# 1. Ensure SSH Key Pair Exists
###############################################################################
if [ ! -f "${SSH_KEY_BASENAME}" ]; then
    echo "🔄 SSH private key '${SSH_KEY_BASENAME}' not found. Generating a new one..."
    ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_BASENAME}" -N "" -C "jumpbox-ssh-key"
    if [ $? -eq 0 ]; then
        echo "✅ SSH keypair generated: '${SSH_KEY_BASENAME}' and '${SSH_KEY_BASENAME}.pub'."
    else
        echo "❌ Failed to generate SSH keypair."
        exit 1
    fi
else
    echo "✅ SSH private key '${SSH_KEY_BASENAME}' already exists."
fi

###############################################################################
# 2. Fix Private Key Permissions
###############################################################################
echo "🔄 Fixing permissions for '${SSH_KEY_BASENAME}'..."
chmod 600 "${SSH_KEY_BASENAME}"
chmod 644 "${SSH_KEY_BASENAME}.pub"

###############################################################################
# 3. Upload Public Key to Jumpbox
###############################################################################
if [ ! -f "${SSH_KEY_BASENAME}.pub" ]; then
    echo "❌ Public key '${SSH_KEY_BASENAME}.pub' not found. Please generate it first."
    exit 1
fi

echo "🔄 Uploading public key to the jumpbox '${JUMPBOX_NAME}'..."
az vm user update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$JUMPBOX_NAME" \
    --username "$USERNAME" \
    --ssh-key-value "$(cat ${SSH_KEY_BASENAME}.pub)"

if [ $? -eq 0 ]; then
    echo "✅ Public key uploaded successfully to '${JUMPBOX_NAME}'."
else
    echo "❌ Failed to upload public key to '${JUMPBOX_NAME}'."
    exit 1
fi

###############################################################################
# 4. SSH into the Jumpbox via Bastion
###############################################################################
echo "🔄 Connecting to the jumpbox '${JUMPBOX_NAME}' via Bastion..."
az network bastion ssh \
    --name "$BASTION_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --target-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$JUMPBOX_NAME" \
    --auth-type "ssh-key" \
    --username "$USERNAME" \
    --ssh-key "${SSH_KEY_BASENAME}"

if [ $? -eq 0 ]; then
    echo "✅ Successfully connected to the jumpbox '${JUMPBOX_NAME}'."
else
    echo "❌ Failed to connect to the jumpbox via Bastion."
    exit 1
fi
