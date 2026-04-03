#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: Please run as root."
   exit 1
fi

echo "🛑 [1/5] Stopping and Disabling HAProxy Service..."
systemctl stop haproxy 2>/dev/null
systemctl disable haproxy 2>/dev/null

echo "🗑️ [2/5] Removing Binary Files..."
# ลบไฟล์ Binary ที่เราก๊อปปี้ไปวางไว้
rm -f /usr/local/sbin/haproxy
rm -f /usr/local/bin/haproxy

echo "📂 [3/5] Removing Configuration and Directories..."
# ลบคอนฟิกและโฟลเดอร์ทำงาน
rm -rf /etc/haproxy
rm -rf /var/lib/haproxy
rm -f /etc/systemd/system/haproxy.service

echo "👤 [4/5] Removing User and Group..."
# ลบ user/group haproxy (ID 188)
userdel haproxy 2>/dev/null
groupdel haproxy 2>/dev/null

echo "🔄 [5/5] Reloading Systemd Daemon..."
systemctl daemon-reload
systemctl reset-failed

echo ""
echo "========================================================"
echo "✨ HAProxy has been successfully REMOVED!"
echo "========================================================"
echo "✅ Service Stopped & Disabled"
echo "✅ Binaries Removed (/usr/local/bin/haproxy)"
echo "✅ Configs Removed (/etc/haproxy)"
echo "✅ User/Group 'haproxy' Removed"
echo "--------------------------------------------------------"
echo "Note: Build dependencies (gcc, make, etc.) were kept."
echo "If you want to remove them, use: apt-get purge build-essential"
echo "========================================================"
