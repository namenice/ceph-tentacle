#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

echo "🛑 [1/5] Stopping and Disabling HAProxy Service..."
systemctl stop haproxy 2>/dev/null
systemctl disable haproxy 2>/dev/null

echo "📦 [2/5] Removing HAProxy Package and PPA..."
# ลบตัวโปรแกรมและไฟล์คอนฟิกพื้นฐาน
apt-get purge -y haproxy 2>/dev/null
apt-get autoremove -y 2>/dev/null

# ลบ PPA Repository ออกจากระบบ
if command -v add-apt-repository >/dev/null; then
    add-apt-repository --remove -y ppa:vbernat/haproxy-3.0 2>/dev/null
fi

echo "📂 [3/5] Cleaning up Modular Directories and Overrides..."
# ลบโฟลเดอร์ conf.d และคอนฟิกทั้งหมด
rm -rf /etc/haproxy

# ลบ Systemd Override (ที่เราใช้แก้ ExecStart และ LimitNOFILE)
rm -rf /etc/systemd/system/haproxy.service.d/

# ลบไฟล์ที่เหลือใน var (ถ้ามี)
rm -rf /var/lib/haproxy

echo "👤 [4/5] Removing User and Group..."
# โดยปกติ apt purge จะไม่ลบ user ให้เพื่อความปลอดภัย แต่เราลบเองได้
userdel haproxy 2>/dev/null
groupdel haproxy 2>/dev/null

echo "🔄 [5/5] Finalizing System Cleanup..."
systemctl daemon-reload
systemctl reset-failed

echo ""
echo "========================================================"
echo "✨ HAProxy Modular Removal: COMPLETED!"
echo "========================================================"
echo "✅ HAProxy Package:     REMOVED"
echo "✅ PPA Repository:      REMOVED"
echo "✅ Modular Configs:     DELETED (/etc/haproxy/conf.d)"
echo "✅ Systemd Overrides:   DELETED"
echo "--------------------------------------------------------"
echo "🚀 Your system is now clean from HAProxy 3.0."
echo "========================================================"
