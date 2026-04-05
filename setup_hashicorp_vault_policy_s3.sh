#!/bin/bash

# --- 1. Configuration ---
export VAULT_ADDR='http://127.0.0.1:8200'
KEY_FILE="/etc/vault.d/vault_keys.txt"
POLICY_NAME="rgw-sse-s3"
POLICY_FILE="/etc/vault.d/rgw-sse-s3-policy.hcl"
ROLE_NAME="rgw-role"
TRANSIT_KEY_NAME="s3-key"

# Check for Root Privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root (sudo)."
   exit 1
fi

# Install jq if not present
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    apt update && apt install -y jq
fi

echo "🛡️ [1/4] Checking Vault Status..."

# Fetch current Vault status
STATUS_JSON=$(vault status -format=json 2>/dev/null)
IS_INIT=$(echo "$STATUS_JSON" | jq -r '.initialized // false')
IS_SEALED=$(echo "$STATUS_JSON" | jq -r '.sealed // true')

# 1. Initialization Logic
if [ "$IS_INIT" == "true" ]; then
    echo "⚠️  Vault is already initialized. Skipping initialization..."
else
    echo "🚀 Initializing Vault..."
    mkdir -p /etc/vault.d
    # Save output to text file for manual recovery if needed
    vault operator init -key-shares=5 -key-threshold=3 > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "✅ Initial Keys and Root Token saved to $KEY_FILE."
    IS_SEALED=true
fi

# 2. Unseal Logic
if [ "$IS_SEALED" == "true" ]; then
    echo "🔓 Vault is SEALED. Starting Unseal process..."
    
    # Extract keys from the key file
    K1=$(grep "Unseal Key 1" "$KEY_FILE" | awk '{print $NF}')
    K2=$(grep "Unseal Key 2" "$KEY_FILE" | awk '{print $NF}')
    K3=$(grep "Unseal Key 3" "$KEY_FILE" | awk '{print $NF}')
    
    vault operator unseal "$K1" > /dev/null
    vault operator unseal "$K2" > /dev/null
    vault operator unseal "$K3" > /dev/null
    echo "✅ Unseal successful."
else
    echo "⚠️  Vault is already UNSEALED. Skipping unseal step..."
fi

# --- 3. Login and Configuration ---
ROOT_TOKEN=$(grep "Initial Root Token" "$KEY_FILE" | awk '{print $NF}')
vault login "$ROOT_TOKEN" > /dev/null

echo "⚙️ [2/4] Configuring Transit Engine & Key..."
vault secrets list -format=json | jq -e '."transit/"' >/dev/null || vault secrets enable transit
vault list -format=json transit/keys 2>/dev/null | jq -e ". | contains([\"$TRANSIT_KEY_NAME\"])" >/dev/null || vault write -f transit/keys/$TRANSIT_KEY_NAME

echo "📄 [3/4] Writing Policy & AppRole..."
cat <<EOF > "$POLICY_FILE"
path "transit/keys/*" { capabilities = ["create", "update", "read", "delete", "list"] }
path "transit/datakey/plaintext/*" { capabilities = ["create", "update"] }
path "transit/decrypt/*" { capabilities = ["update"] }
EOF
vault policy write "$POLICY_NAME" "$POLICY_FILE" > /dev/null

vault auth list -format=json | jq -e '."approle/"' >/dev/null || vault auth enable approle
vault write auth/approle/role/$ROLE_NAME token_policies="$POLICY_NAME" token_ttl=1h token_max_ttl=4h > /dev/null

# --- 4. Extract and Save Role_ID & Secret_ID ---
echo "✨ [4/4] Saving Credentials to $KEY_FILE..."

# Extract IDs using jq
ROLE_ID=$(vault read -format=json auth/approle/role/$ROLE_NAME/role-id | jq -r '.data.role_id')
SECRET_ID=$(vault write -f -format=json auth/approle/role/$ROLE_NAME/secret-id | jq -r '.data.secret_id')

# Clean up old entries in the key file to prevent duplicates
sed -i '/Role ID:/d' "$KEY_FILE"
sed -i '/Secret ID:/d' "$KEY_FILE"

# Append new credentials to the end of the file
echo "Role ID: $ROLE_ID" >> "$KEY_FILE"
echo "Secret ID: $SECRET_ID" >> "$KEY_FILE"

echo ""
echo "========================================================"
echo "🎯 VAULT SERVER SETUP COMPLETED!"
echo "========================================================"
echo "✅ Role ID   : $ROLE_ID"
echo "✅ Secret ID : $SECRET_ID"
echo "--------------------------------------------------------"
echo "📁 All information saved in: $KEY_FILE"
echo "💡 To extract values for your agent script, use:"
echo "   grep 'Role ID' $KEY_FILE | awk '{print \$NF}'"
echo "========================================================"
