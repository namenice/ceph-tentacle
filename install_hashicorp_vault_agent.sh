#!/bin/bash

# --- 1. Configuration ---
VAULT_SERVER_URL="http://172.71.1.184:8200"
AGENT_BASE_DIR="/etc/vault.d/agent"
AUTH_DIR="$AGENT_BASE_DIR/auth"
AGENT_CONFIG="$AGENT_BASE_DIR/agent-config.hcl"
# Source file containing IDs
KEY_FILE="/etc/vault.d/.vault_keys.txt"

# Check for Root Privileges
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root (sudo)."
   exit 1
fi

echo "🛡️ [1/5] Checking Source Credentials..."

# Verify if the source key file exists
if [ ! -f "$KEY_FILE" ]; then
    echo "❌ Error: Source file $KEY_FILE not found."
    echo "Please ensure the Vault Server setup script has been run successfully."
    exit 1
fi

# Extract Role ID and Secret ID automatically
ROLE_ID=$(grep "Role ID" "$KEY_FILE" | awk '{print $NF}')
SECRET_ID=$(grep "Secret ID" "$KEY_FILE" | awk '{print $NF}')

# Check if extracted values are empty
if [ -z "$ROLE_ID" ] || [ -z "$SECRET_ID" ]; then
    echo "❌ Error: Could not extract Role ID or Secret ID from $KEY_FILE."
    exit 1
fi

echo "✅ Credentials successfully loaded."

echo "🚀 [2/5] Installing Vault Binary..."
if ! command -v vault &> /dev/null; then
    apt update && apt install -y gpg coreutils curl wget
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt update && apt install -y vault
else
    echo "✅ Vault is already installed."
fi

echo "📂 [3/5] Setting up Directory Structure..."
mkdir -p "$AUTH_DIR"

# Initialize sink and cache files
touch "$AGENT_BASE_DIR/.vault-token"
touch "$AGENT_BASE_DIR/.vault-agent-cache.json"

# Write RoleID and SecretID to Agent's specific auth files
echo "$ROLE_ID" > "$AUTH_DIR/role-id"
echo "$SECRET_ID" > "$AUTH_DIR/secret-id"

# Set ownership to vault user
chown -R vault:vault "$AGENT_BASE_DIR"
chmod 600 "$AUTH_DIR/role-id" "$AUTH_DIR/secret-id"

echo "📄 [4/5] Creating Agent Configuration: agent-config.hcl..."
cat <<EOF | tee "$AGENT_CONFIG" > /dev/null
vault {
  address = "$VAULT_SERVER_URL"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "$AUTH_DIR/role-id"
      secret_id_file_path = "$AUTH_DIR/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "$AGENT_BASE_DIR/.vault-token"
    }
  }
}

cache {
  use_auto_auth_token = true
  path = "$AGENT_BASE_DIR/.vault-agent-cache.json"
}

listener "tcp" {
  address     = "0.0.0.0:8100"
  tls_disable = 1
}
EOF

echo "⚙️ [5/5] Configuring Systemd Service..."
cat <<EOF | tee /etc/systemd/system/vault-agent.service > /dev/null
[Unit]
Description=Vault Agent Service (Auto-auth for RGW)
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault agent -config=$AGENT_CONFIG
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Restarting and Enabling Service..."
systemctl daemon-reload
systemctl enable vault-agent
systemctl restart vault-agent

echo ""
echo "========================================================"
echo "🎯 VAULT AGENT AUTO-SETUP COMPLETED!"
echo "========================================================"
sleep 2
systemctl status vault-agent --no-pager
echo "--------------------------------------------------------"
echo "🔍 Health Check (Local Listener 8100):"
curl -s http://127.0.0.1:8100/v1/sys/health | grep -o '"initialized":true' || echo "⚠️ Warning: Agent not ready yet. Check logs."
echo "--------------------------------------------------------"
echo "📍 Config File : $AGENT_CONFIG"
echo "📍 Auth Method : AppRole (Automatic)"
echo "📍 Token Sink  : $AGENT_BASE_DIR/.vault-token"
echo "========================================================"
