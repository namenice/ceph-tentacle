#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "🔐 [Start] Installing HashiCorp Vault on Ubuntu 22.04..."

# --- 2. Install Prerequisites ---
echo "📦 Installing dependencies..."
apt update && apt install -y gpg coreutils curl wget

# --- 3. Add HashiCorp GPG Key ---
echo "🔑 Adding HashiCorp GPG key..."
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# --- 4. Add HashiCorp Repository ---
echo "📂 Adding HashiCorp repository..."
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
tee /etc/apt/sources.list.d/hashicorp.list

# --- 5. Install Vault ---
echo "🛠️ Installing Vault..."
apt update && apt install -y vault

# --- 6. Basic Configuration (Dev Mode Placeholder) ---
# หมายเหตุ: สำหรับ Production คุณต้องแก้ไฟล์ /etc/vault.d/vault.hcl เอง
echo "⚙️ Configuring basic storage path..."
mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault/data

# --- 7. Enable and Start Service ---
echo "🚀 Enabling Vault service..."
systemctl enable vault

echo ""
echo "========================================================"
echo "🎯 VAULT INSTALLATION COMPLETED!"
echo "========================================================"
echo "✅ Vault Version : $(vault version)"
echo "✅ Binary Path   : $(which vault)"
echo "✅ Service File  : /lib/systemd/system/vault.service"
echo "✅ Config File   : /etc/vault.d/vault.hcl"
echo "--------------------------------------------------------"
echo "💡 NEXT STEPS:"
echo "1. Edit /etc/vault.d/vault.hcl to set your IP/Storage."
echo "2. Run 'systemctl start vault' to begin."
echo "3. Run 'vault operator init' to initialize your vault."
echo "========================================================"
