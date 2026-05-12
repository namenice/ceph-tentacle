#!/bin/bash

# --- 1. Check Root Privilege ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run as root."
   exit 1
fi

# --- 2. OS Version Validation (Fix for Ubuntu 22.04) ---
OS_ID=$(grep -w "ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')

echo "🔍 Checking OS Compatibility..."
if [[ "$OS_ID" == "ubuntu" ]] && [[ "$OS_VERSION" == "22.04" ]]; then
    echo "✅ OS Verified: Ubuntu $OS_VERSION (Jammy Jellyfish)"
else
    echo "❌ Error: This script is strictly for Ubuntu 22.04."
    echo "Detected: $OS_ID $OS_VERSION"
    exit 1
fi

echo "🚀 [Start] Preparing Host for Ceph RGW..."

# --- 3. Set Timezone ---
timedatectl set-timezone Asia/Bangkok

# --- 4. Update System & Install Core Dependencies ---
echo "📦 Updating packages and installing dependencies..."
apt update && apt upgrade -y
apt install -y curl wget vim python3 python3-pip lvm2 chrony \
            apt-transport-https ca-certificates \
            dbus-user-session python3-distutils

# --- 5. Disable Swap ---
echo "🚫 Disabling Swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# --- 6. Enable Chrony (Time Sync) ---
echo "⏰ Starting Time Sync service..."
systemctl enable --now chrony
systemctl restart chrony
sleep 2 # รอให้ service เริ่มต้นสักครู่

# --- 7. Kernel Tuning ---
echo "⚙️ Tuning Kernel Parameters..."
cat <<EOF | tee /etc/sysctl.d/90-ceph.conf > /dev/null
# Networking: รองรับ High Throughput สำหรับ OSD 16 ลูก
net.core.somaxconn = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

# TCP Buffer: ขยายเป็น 64MB เพื่อรองรับการส่งข้อมูลก้อนใหญ่ (Large Objects)
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# Memory Safety: สำหรับเครื่อง RAM 376GB
vm.swappiness = 5
vm.min_free_kbytes = 4194304  # กั้น RAM 4GB ไว้ให้ Kernel ป้องกันเครื่องค้างตอน I/O Peak
vm.max_map_count = 262144

# File System: ตั้งให้สัมพันธ์กับ ulimit nofile
fs.file-max = 4194304
EOF
sudo sysctl --system > /dev/null

# --- 8. Set Resource Limits (Ulimits) ---
# --- Resource Limits (/etc/security/limits.d/ceph.conf) ---
echo "📋 Configuring Resource Limits (nofile only)..."
cat <<EOF | sudo tee /etc/security/limits.d/ceph.conf > /dev/null
# ขยายเพดานการเปิดไฟล์เป็น 1 ล้าน (Mandatory for Ceph OSD/RGW)
* soft nofile 1048576
* hard nofile 1048576
EOF

# --- Summary of Actions ---
echo ""
echo "========================================================"
echo "🎯 HOST PREPARATION COMPLETED!"
echo "========================================================"
echo "✅ OS Check     : Ubuntu 22.04 (PASS)"
echo "✅ Timezone     : $(date) (Asia/Bangkok)"
echo "✅ Swap Status  : DISABLED (Permanent)"
echo "✅ SSH Server   : Installed & Running"
echo "✅ Kernel/Lim   : Optimized for High-concurrency RGW"
echo "✅ Time Sync    : Chrony service is active"
echo "--------------------------------------------------------"
echo "👉 NEXT STEP: REBOOT now, then proceed with:"
echo "   1. curl --silent --remote-name --location https://download.ceph.com/rpm-20.2.0/el9/noarch/cephadm"
echo "   2. chmod +x cephadm"
echo "   3. mv cephadm /usr/local/bin/" 
echo "   4. cephadm install podman"
echo "   5. cephadm bootstrap --mon-ip <IP>"
echo "========================================================"
