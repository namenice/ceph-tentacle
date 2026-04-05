#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "🛡️ [Start] Uninstalling Vault Server and Agent..."

# --- 2. Stop and Disable Services ---
echo "🛑 Stopping Vault services..."
systemctl stop vault vault-agent 2>/dev/null
systemctl disable vault vault-agent 2>/dev/null

# --- 3. Remove Systemd Service Files ---
echo "🗑️ Removing service files..."
rm -f /etc/systemd/system/vault-agent.service
rm -f /lib/systemd/system/vault.service
systemctl daemon-reload

# --- 4. Uninstall Vault Package ---
echo "📦 Uninstalling Vault package via apt..."
apt purge -y vault
apt autoremove -y

# --- 5. Clean Up Directories and Data ---
# คำเตือน: ข้อมูลใน Vault (Keys/Secrets) จะหายถาวร
echo "📂 Cleaning up configuration and data directories..."
rm -rf /etc/vault.d
rm -rf /opt/vault/data
rm -rf /var/lib/vault
rm -rf /etc/apt/sources.list.d/hashicorp.list
rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg

# --- 6. Remove Vault User/Group ---
echo "👤 Removing vault user and group..."
userdel -r vault 2>/dev/null
groupdel vault 2>/dev/null

echo ""
echo "========================================================"
echo "🎯 UNINSTALLATION COMPLETED!"
echo "========================================================"
echo "✅ Services stopped and disabled."
echo "✅ Binaries and Packages removed."
echo "✅ Config and Data directories wiped (/etc/vault.d, /opt/vault)."
echo "✅ Repository and GPG keys removed."
echo "--------------------------------------------------------"
echo "💡 System is now clean from HashiCorp Vault."
echo "========================================================"
