#!/bin/bash

# ตรวจสอบสิทธิ์ Root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: Please run as root (use sudo)"
   exit 1
fi

echo "--- Starting Keepalived Removal & Cleanup ---"

# 1. หยุดการทำงานและปิด Service
echo "🛑 Stopping and disabling Keepalived service..."
systemctl stop keepalived 2>/dev/null
systemctl disable keepalived 2>/dev/null

# 2. ถอนการติดตั้ง Package (ใช้ purge เพื่อลบคอนฟิกเริ่มต้นด้วย)
echo "📦 Removing Keepalived package..."
apt purge -y keepalived
apt autoremove -y

# 3. ลบคอนฟิกไฟล์ที่สร้างขึ้นมาเอง
echo "🗑️ Cleaning up configuration files..."
rm -f /etc/keepalived/keepalived.conf
rm -rf /etc/keepalived/

# 4. ลบค่า Kernel Tuning (sysctl)
echo "⚙️ Reverting Kernel settings..."
if [ -f /etc/sysctl.d/90-keepalived.conf ]; then
    rm -f /etc/sysctl.d/90-keepalived.conf
    # โหลดค่า sysctl ใหม่เพื่อคืนค่าเดิม
    sysctl --system > /dev/null
    echo "✅ Sysctl settings reverted."
fi

# 5. ตรวจสอบว่า Virtual IP (VIP) ยังค้างอยู่หรือไม่
# (บางครั้งถ้าดับ service ไม่สะอาด VIP อาจจะค้างที่ Interface)
echo "🔍 Checking for leftover VIP..."
# ดึงข้อมูล VIP จากตัวแปรต้นฉบับ (หรือตรวจสอบจาก Interface โดยตรง)
# ในที่นี้จะช่วยเตือนถ้าเจอ IP ที่หน้าตาเหมือน VIP ค้างอยู่
IP_CHECK=$(ip addr show | grep "192.168.17.102")
if [ ! -z "$IP_CHECK" ]; then
    echo "⚠️  Warning: Virtual IP might still be attached to the interface."
    echo "You might need to manually run: sudo ip addr del 192.168.17.102/32 dev ens160"
fi

echo "========================================================"
echo "✨ Keepalived has been successfully removed."
echo "========================================================"
