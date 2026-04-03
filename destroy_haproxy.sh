#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "🛑 [1/6] Stopping and Disabling HAProxy Service..."
systemctl stop haproxy 2>/dev/null
systemctl disable haproxy 2>/dev/null

echo "📦 [2/6] Removing HAProxy via APT (if installed)..."
# ลบ package และ config ที่มากับ apt
apt-get purge -y haproxy 2>/dev/null
apt-get autoremove -y 2>/dev/null

echo "🗑️ [3/6] Cleaning up Manual Compiled Binaries..."
# ลบไฟล์ที่เกิดจากการ 'make install' และที่เรา copy เอง
rm -f /usr/local/sbin/haproxy
rm -f /usr/local/bin/haproxy
rm -f /usr/sbin/haproxy

echo "📂 [4/6] Removing Configuration and Systemd Files..."
# ลบโฟลเดอร์คอนฟิกและไฟล์ service ที่เราสร้างเอง
rm -rf /etc/haproxy
rm -rf /var/lib/haproxy
rm -f /etc/systemd/system/haproxy.service
rm -rf /etc/systemd/system/haproxy.service.d/ # ลบ drop-in limits ที่เราสร้างไว้

echo "👤 [5/6] Removing User and Group..."
# ลบ user/group haproxy (ถ้ายังมีอยู่)
userdel haproxy 2>/dev/null
groupdel haproxy 2>/dev/null

echo "🔄 [6/6] Finalizing System Cleanup..."
systemctl daemon-reload
systemctl reset-failed

# ลบ PPA (ถ้าต้องการลบแหล่งติดตั้งออกด้วย)
# add-apt-repository --remove -y ppa:vbernat/haproxy-3.0 2>/dev/null

echo ""
echo "========================================================"
echo "✨ HAProxy Deep Clean: COMPLETED!"
echo "========================================================"
echo "✅ All Binaries (Local & APT) removed"
echo "✅ Configuration /etc/haproxy deleted"
echo "✅ Systemd services cleared"
echo "✅ User/Group 'haproxy' removed"
echo "--------------------------------------------------------"
echo "🚀 Now you can run the HAProxy 3.0 PPA script safely."
echo "========================================================"
