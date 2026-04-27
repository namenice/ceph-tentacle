#!/bin/bash

# ========================================================
# ⚙️ CONFIGURATION ENVIRONMENT (ให้ตรงกับสคริปต์ติดตั้ง)
# ========================================================
SOURCE_DIR="/root/data/"
CONFIG_PATH="/etc/lsyncd/lsyncd.conf.lua"
LOG_DIR="/var/log/lsyncd"
# ========================================================

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "🧹 [Start] Removing Lsyncd and Cleaning up system..."

# --- 2. Stop and Disable Service ---
echo "🛑 Stopping and disabling Lsyncd service..."
systemctl stop lsyncd > /dev/null 2>&1
systemctl disable lsyncd > /dev/null 2>&1
echo "✅ Service: Stopped & Disabled"

# --- 3. Uninstall Lsyncd ---
echo "📦 Uninstalling lsyncd package..."
apt purge -y lsyncd > /dev/null 2>&1
apt autoremove -y > /dev/null 2>&1
echo "✅ Package: Uninstalled"

# --- 4. Remove Configuration and Logs ---
echo "🗑️ Removing configuration files and logs..."
rm -rf /etc/lsyncd
rm -rf $LOG_DIR
echo "✅ Config & Logs: Deleted"

# --- 5. Optional: Clean Source Directory ---
# หมายเหตุ: เราจะไม่ลบข้อมูลใน SOURCE_DIR อัตโนมัติเพื่อความปลอดภัย 
# แต่จะถามคุณก่อนว่าต้องการลบไหม
echo ""
read -p "❓ Do you want to delete the source directory ($SOURCE_DIR)? [y/N]: " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    rm -rf $SOURCE_DIR
    echo "✅ Source Directory: Deleted"
else
    echo "📂 Source Directory: Kept at $SOURCE_DIR"
fi

echo ""
echo "========================================================"
echo "✨ LSYNCD REMOVAL COMPLETED!"
echo "========================================================"
echo "✅ Service & Package : Removed"
echo "✅ Configuration     : Deleted"
echo "✅ Logs              : Deleted"
echo "--------------------------------------------------------"
echo "💡 Note: The target host ($TARGET_IP) remains untouched."
echo "   SSH keys in ~/.ssh/authorized_keys on target host"
echo "   are still there. Remove them manually if needed."
echo "========================================================"
