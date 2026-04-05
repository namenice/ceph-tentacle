#!/bin/bash

# --- Check Root ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ โปรดรันด้วยสิทธิ์ root"
   exit 1
fi

echo "🛡️ [Vault Server] เริ่มการถอนการติดตั้ง..."

# 1. หยุดและยกเลิก Service
systemctl stop vault 2>/dev/null
systemctl disable vault 2>/dev/null

# 2. ลบไฟล์ Service และล้างคำสั่งระบบ
rm -f /lib/systemd/system/vault.service
systemctl daemon-reload

# 3. ลบ Package และ Binary
apt purge -y vault 2>/dev/null
rm -f /usr/bin/vault /usr/local/bin/vault

# 4. ลบข้อมูลและ Config (ข้อมูลความลับจะหายถาวร!)
rm -rf /etc/vault.d
rm -rf /opt/vault
rm -rf /var/lib/vault

# 5. ลบ Repository และ User
rm -f /etc/apt/sources.list.d/hashicorp.list
rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
userdel -r vault 2>/dev/null

echo "✅ ถอนการติดตั้ง Vault Server เรียบร้อย"

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
