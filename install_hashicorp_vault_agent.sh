#!/bin/bash

# --- Configuration ---
VAULT_SERVER_URL="http://172.71.1.184:8200"
# ปรับ Path หลักไปที่ /etc/vault.d/agent/
AGENT_BASE_DIR="/etc/vault.d/agent"
AUTH_DIR="$AGENT_BASE_DIR/auth"
AGENT_CONFIG="$AGENT_BASE_DIR/agent-config.hcl"

# ตรวจสอบสิทธิ์ Root
if [[ $EUID -ne 0 ]]; then
   echo "❌ โปรดรันสคริปต์นี้ด้วยสิทธิ์ root (sudo)"
   exit 1
fi

# รับค่า RoleID และ SecretID
read -p "🔑 กรอก RoleID: " ROLE_ID
read -p "🔑 กรอก SecretID: " SECRET_ID

echo "🚀 [1/5] ติดตั้ง Vault Binary..."
if ! command -v vault &> /dev/null; then
    apt update && apt install -y gpg coreutils curl wget
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt update && apt install -y vault
else
    echo "✅ Vault ติดตั้งอยู่แล้ว"
fi

echo "📂 [2/5] เตรียมโครงสร้างโฟลเดอร์ใน $AGENT_BASE_DIR..."
# สร้าง Directory แบบ Recursive
mkdir -p "$AUTH_DIR"

# สร้างไฟล์หลอกสำหรับ Sink และ Cache ใน Path ใหม่
touch "$AGENT_BASE_DIR/.vault-token"
touch "$AGENT_BASE_DIR/.vault-agent-cache.json"

# เขียน RoleID และ SecretID
echo "$ROLE_ID" > "$AUTH_DIR/role-id"
echo "$SECRET_ID" > "$AUTH_DIR/secret-id"

# ตั้งสิทธิ์ให้ user vault เข้าถึง Folder Agent
chown -R vault:vault "$AGENT_BASE_DIR"
chmod 600 "$AUTH_DIR/role-id" "$AUTH_DIR/secret-id"

echo "📄 [3/5] สร้างไฟล์ config: agent-config.hcl..."
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

echo "⚙️ [4/5] สร้าง Systemd Service (ปรับ Path Config)..."
cat <<EOF | tee /etc/systemd/system/vault-agent.service > /dev/null
[Unit]
Description=Vault Agent Service (Auto-auth for RGW)
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
# ชี้ไปที่ Path ใหม่
ExecStart=/usr/bin/vault agent -config=$AGENT_CONFIG
Restart=always
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 [5/5] เริ่มการทำงานของ Service..."
systemctl daemon-reload
systemctl enable vault-agent
systemctl restart vault-agent

echo ""
echo "========================================================"
echo "🎯 VAULT AGENT SETUP COMPLETED (NEW PATH)!"
echo "========================================================"
sleep 2
systemctl status vault-agent --no-pager
echo "--------------------------------------------------------"
echo "🔍 ตรวจสอบสุขภาพ (Listener 8100):"
curl -s http://127.0.0.1:8100/v1/sys/health | grep -o '"initialized":true' || echo "⚠️  คำเตือน: Agent ยังไม่พร้อม"
echo "--------------------------------------------------------"
echo "📍 Config File : $AGENT_CONFIG"
echo "📍 Token Sink  : $AGENT_BASE_DIR/.vault-token"
echo "========================================================"
