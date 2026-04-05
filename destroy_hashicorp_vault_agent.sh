#!/bin/bash

# --- Check Root ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ โปรดรันด้วยสิทธิ์ root"
   exit 1
fi

echo "🐙 [Vault Agent] เริ่มการถอนการติดตั้ง..."

# 1. หยุดและยกเลิก Service ของ Agent
systemctl stop vault-agent 2>/dev/null
systemctl disable vault-agent 2>/dev/null

# 2. ลบไฟล์ Service ที่เราสร้างแบบ Manual
rm -f /etc/systemd/system/vault-agent.service
systemctl daemon-reload

# 3. ลบ Config และไฟล์ยืนยันตัวตน (Role-ID, Secret-ID, Token)
# เราลบเฉพาะส่วนที่เกี่ยวกับ Agent เพื่อความปลอดภัย
rm -f /etc/vault.d/agent-config.hcl
rm -rf /etc/vault.d/auth
rm -f /etc/vault.d/.vault-token
rm -f /etc/vault.d/.vault-agent-cache.json

# 4. ลบ Binary ของ Vault ออกจากเครื่อง Client
apt purge -y vault 2>/dev/null
apt autoremove -y 2>/dev/null

echo "✅ ถอนการติดตั้ง Vault Agent และล้างไฟล์ Auth เรียบร้อย"
